# Posting announcements to Discord

A GitHub Action ([`.github/workflows/discord-post.yml`](.github/workflows/discord-post.yml))
posts announcements from `announcements.json` to a Discord channel **on a schedule**.
You queue announcements ahead of time and each one auto-posts when its time arrives —
no daily manual pushing.

## One-time setup

### 1. Create a Discord webhook

In Discord: **Channel → Edit Channel → Integrations → Webhooks → New Webhook**.
Name it (e.g. "Announcements"), pick the target channel, and **Copy Webhook URL**.

### 2. Add it as a repo secret

GitHub → repo **Settings → Secrets and variables → Actions → New repository secret**:

- **Name:** `DISCORD_ANNOUNCEMENT_WEBHOOK_URL`
- **Value:** the webhook URL you copied

### 3. (One time) confirm it works

GitHub → **Actions → "Post announcements to Discord" → Run workflow**. With the seeded
ledger, nothing should post (all current announcements are already marked). Add a test
announcement with a past time to verify, then remove it.

## How scheduling works

When the cron runs (hourly), an announcement is posted **once** when:

- its scheduled time has arrived — `discord_post_at` if set, otherwise `valid_from`,
  otherwise immediately; **and**
- it isn't expired (`valid_until` in the past); **and**
- it hasn't been posted before (tracked in `.discord/posted.json`).

So to schedule a post, just set the time and merge it whenever you like — even a week early.

### Schedule the Discord post separately from the extension

`valid_from` controls when the announcement appears in the VS Code extension **and**, by
default, when it posts to Discord. To post to Discord at a *different* time, add an
optional `discord_post_at`:

```jsonc
{
  "id": "my-event-2026",
  "title": "My Event",
  "body": "Details here.",
  "valid_from": "2026-07-01T00:00:00Z",       // appears in extension at this time
  "discord_post_at": "2026-07-01T16:00:00Z",  // posts to Discord at 9am PT instead
  "valid_until": "2026-07-08T23:59:59Z"
}
```

Times are UTC (ISO-8601). 9am Pacific ≈ `16:00:00Z` (PDT) / `17:00:00Z` (PST).
Posting lands within ~an hour of the scheduled time (GitHub cron is best-effort).

### Custom Discord message format (`discord_content`)

By default the post is a **rich embed** built from `title` / `body` / `link` /
`priority`. To instead post a **plain announcement-channel message** — with an
`@everyone` ping, custom emoji, bullet lines, and raw URLs — add an optional
`discord_content`. When present, it's posted **verbatim** as the message content
and the embed is skipped. This copy is Discord-only; the VS Code extension still
shows `title` / `body`.

```jsonc
{
  "id": "rocketride-harness-engineering-demo-2026",
  "title": "...",   // extension only
  "body": "...",     // extension only
  "discord_content": "Hello @everyone <:RocketRideiconWhite:123456789012345678>\n\nCheck out the new demo of Joe Maionchi...\n\n⚡ Pipeline built in under 30 seconds\n🖥️ Running locally + offline\n⚙️ C++ runtime · 64 parallel threads\n\n🗓️ RocketRide Cloud launches June 18 at Shack15, San Francisco.\n👉 RSVP: https://lu.ma/...\nCheckout the Demo: https://www.linkedin.com/...",
  "discord_post_at": "2026-06-05T16:00:00Z"
}
```

Formatting rules to know:

- **`@everyone`** only pings from message content (not embeds); the workflow sets
  `allowed_mentions: { parse: ["everyone"] }` so it fires. The webhook must be
  allowed to mention everyone in the target channel.
- **Custom emoji** must use the `<:name:id>` form, not `:name:`. To get the id,
  type `\:emojiname:` in Discord and send — it reveals the raw `<:name:id>`.
- **Labeled links** (`[text](url)`) do **not** render in plain content — only in
  embeds. In `discord_content`, put the full URL (optionally on its own line so
  Discord shows a preview).

## The ledger (`.discord/posted.json`)

A list of announcement ids already posted. The workflow appends to it and commits the
change back, so re-runs never double-post. **Don't hand-edit it** unless you want to
force a re-post (remove an id) or suppress one (add an id).

## Notes & gotchas

- **Editing an already-posted announcement won't re-post it.** Give it a new `id` (the
  README already recommends this for substantive edits) to send an updated post.
- **Branch protection:** the workflow pushes the ledger commit to `main`. If `main`
  requires PRs for *all* pushes, the commit step will fail — exempt
  `github-actions[bot]`, or move the ledger to a dedicated branch.
- **Expired announcements** are marked handled (never posted late) if their `valid_until`
  has already passed by the time the cron sees them.
