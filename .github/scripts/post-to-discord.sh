#!/usr/bin/env bash
#
# Post scheduled announcements to a Discord channel via an Incoming Webhook.
#
# How scheduling works:
#   - An announcement becomes eligible once its scheduled time has arrived.
#     The scheduled time is `discord_post_at` if present, else `valid_from`,
#     else "immediately".
#   - Expired announcements (now > valid_until) are never posted.
#   - Each announcement is posted at most once. Posted ids are recorded in the
#     ledger (.discord/posted.json) so re-runs of the cron never double-post.
#
# Env:
#   DISCORD_ANNOUNCEMENT_WEBHOOK_URL  (required)  Discord channel Incoming Webhook URL.
#
set -euo pipefail

WEBHOOK="${DISCORD_ANNOUNCEMENT_WEBHOOK_URL:?DISCORD_ANNOUNCEMENT_WEBHOOK_URL is not set}"
ANN_FILE="announcements.json"
LEDGER=".discord/posted.json"

mkdir -p "$(dirname "$LEDGER")"
[ -f "$LEDGER" ] || echo "[]" > "$LEDGER"

now_epoch=$(date -u +%s)

# Discord embed sidebar color (decimal) per priority.
color_for() {
  case "$1" in
    urgent)  echo 15158332 ;;  # red
    warning) echo 16098851 ;;  # amber
    *)       echo 3447003  ;;  # blue (info / default)
  esac
}

count=$(jq '.announcements | length' "$ANN_FILE")

for i in $(seq 0 $((count - 1))); do
  id=$(jq -r ".announcements[$i].id" "$ANN_FILE")

  # Already posted? Skip.
  if jq -e --arg id "$id" 'index($id) != null' "$LEDGER" >/dev/null; then
    continue
  fi

  valid_from=$(jq -r ".announcements[$i].valid_from // empty" "$ANN_FILE")
  valid_until=$(jq -r ".announcements[$i].valid_until // empty" "$ANN_FILE")
  post_at=$(jq -r ".announcements[$i].discord_post_at // empty" "$ANN_FILE")

  # When should this go to Discord? discord_post_at > valid_from > now.
  schedule_ts="${post_at:-$valid_from}"
  if [ -n "$schedule_ts" ]; then
    sched_epoch=$(date -u -d "$schedule_ts" +%s)
    if [ "$now_epoch" -lt "$sched_epoch" ]; then
      continue  # not time yet
    fi
  fi

  # Past its valid window? Don't post, but mark as handled so we never post it late.
  if [ -n "$valid_until" ]; then
    vu_epoch=$(date -u -d "$valid_until" +%s)
    if [ "$now_epoch" -gt "$vu_epoch" ]; then
      echo "Skipping expired (marking handled): $id"
      tmp=$(mktemp)
      jq --arg id "$id" '. + [$id]' "$LEDGER" > "$tmp" && mv "$tmp" "$LEDGER"
      continue
    fi
  fi

  # Two posting modes:
  #   1. discord_content present → post it verbatim as a plain-content message.
  #      Lets you write the full announcement-channel format: an @everyone ping,
  #      custom emoji (<:name:id>), bullet lines, and raw URLs. allowed_mentions
  #      lets the @everyone actually fire. This copy is Discord-only; it does NOT
  #      affect what the VS Code extension shows (that still uses title/body).
  #   2. otherwise → a rich embed derived from title/body/link/priority.
  discord_content=$(jq -r ".announcements[$i].discord_content // empty" "$ANN_FILE")

  if [ -n "$discord_content" ]; then
    payload=$(jq -n \
      --arg content "$discord_content" \
      '{ content: $content, allowed_mentions: { parse: ["everyone"] } }')
  else
    # Strip leading Markdown image (e.g. "![alt](assets/icon.svg) ") from the title;
    # Discord embed titles don't render it.
    title=$(jq -r ".announcements[$i].title" "$ANN_FILE" | sed -E 's/!\[[^]]*\]\([^)]*\)[[:space:]]*//g')
    body=$(jq -r ".announcements[$i].body" "$ANN_FILE")
    link=$(jq -r ".announcements[$i].link // empty" "$ANN_FILE")
    priority=$(jq -r ".announcements[$i].priority // \"info\"" "$ANN_FILE")
    color=$(color_for "$priority")

    payload=$(jq -n \
      --arg title "$title" \
      --arg desc "$body" \
      --arg url "$link" \
      --argjson color "$color" \
      '{ embeds: [
          ( { title: $title, description: $desc, color: $color }
            + (if $url == "" then {} else { url: $url } end) )
        ] }')
  fi

  echo "Posting: $id"
  http_code=$(curl -sS -o /tmp/discord_resp -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST -d "$payload" "$WEBHOOK")

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    tmp=$(mktemp)
    jq --arg id "$id" '. + [$id]' "$LEDGER" > "$tmp" && mv "$tmp" "$LEDGER"
    sleep 1  # be gentle with Discord rate limits when posting a batch
  else
    echo "::error::Failed to post $id (HTTP $http_code): $(cat /tmp/discord_resp)" >&2
  fi
done
