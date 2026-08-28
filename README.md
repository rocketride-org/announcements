# RocketRide Announcements

`announcements.json` is the content source for the announcements panel in the [RocketRide VS Code extension](https://github.com/rocketride-org/rocketride-server). The extension fetches this file at startup from `raw.githubusercontent.com`, caches it locally for an hour, and falls back to a bundled defaults list if the fetch fails.

Hosting an announcement here means it shows up in every running extension within an hour of merge, with no release cycle required and no admin UI to build. Updates are gated by [`CODEOWNERS`](.github/CODEOWNERS): any change to `announcements.json` requires PR review from a listed owner.

## Schema

```jsonc
{
  "schema_version": 1,
  "announcements": [
    {
      "id": "string",                  // stable identifier; clients dedupe + remember "dismissed" state by id
      "title": "string",               // shown in the panel header, ~60 chars
      "body": "string",                // shown below the title; inline Markdown, ≤2 sentences, no emoji
      "priority": "info|warning|urgent", // controls color + ordering
      "valid_from": "YYYY-MM-DDTHH:MM:SSZ", // optional, ISO-8601 UTC; if absent, valid immediately
      "valid_until": "YYYY-MM-DDTHH:MM:SSZ", // optional; if absent, valid indefinitely
      "link": "string",                // optional, full URL shown as a "Learn more" button
      "dismissable": true              // if false, panel cannot be dismissed by user
    }
  ]
}
```

### Field guidance

- **`id`** — pick something descriptive and stable across edits. The extension remembers which ids the user dismissed; reusing an old `id` after the user dismissed it means they won't see the new content. Bump to a new `id` if the message materially changes.
- **`title`** — short, plain text (~60 chars). The leading glyph is a Markdown image referencing a file in [`assets/`](assets/) (e.g. `![RocketRide](assets/rocketride.svg)`) — add visuals that way, not with emoji.
- **`body`** — keep it to **two sentences at most** and **no emoji** (emoji read as cheap in-product). Inline Markdown is supported (`**bold**`, links, `` `code` ``); if you want a graphic, commit it under [`assets/`](assets/) and reference it with Markdown image syntax rather than inlining an emoji.
- **`schema_version`** — current is `1`. Old extension builds ignore fields they don't recognize; bumping `schema_version` signals a structural change (e.g., adding a required field).
- **`priority`** — `urgent` floats to the top and uses red styling; reserve for outages and security advisories. `warning` is yellow (degraded service, deprecation notices). `info` is blue (releases, events, feature highlights). Default if absent: `info`.
- **`valid_from` / `valid_until`** — let you queue future announcements (drop the JSON into a PR ahead of time) and auto-expire stale ones. Both optional.
- **`link`** — if set, the extension renders a "Learn more" button that opens the URL externally. Keep links to canonical sources (docs, blog posts, GitHub issues).
- **`dismissable`** — default `true`. Set to `false` only for legal/compliance notices that must stay visible.

## Adding an announcement

1. Open a PR that edits `announcements.json` only.
2. Make sure the JSON is valid (lint with `jq . announcements.json` locally; CI will reject malformed JSON).
3. Wait for review + merge from a CODEOWNER. The change is live within an hour (extension cache TTL).

## Removing or editing

- **To take an announcement down immediately**: set `valid_until` to a past timestamp, or delete the entry. The extension will stop showing it on its next refresh.
- **To edit copy**: change `title` / `body` in place. If the change is substantive enough that a previously-dismissing user should see it again, bump the `id`.

## Why a separate repo

- **Independent release cadence**: announcement content shouldn't gate on the engine release cycle (`rocketride-server`) — most announcements need to ship faster than that, and engine releases shouldn't be blocked on copy edits.
- **Public read access**: published from `raw.githubusercontent.com`, so the extension fetches it without auth and GitHub handles global CDN caching.
- **Audit trail + review gate**: git history shows who said what, when, and why; CODEOWNERS keeps the change set small.

## Operational notes

- The fetch URL is `https://raw.githubusercontent.com/rocketride-org/announcements/main/announcements.json` — pinned to `main` branch.
- Raw content is served via GitHub's CDN with a ~5 minute default TTL per IP; updates propagate globally within that window. Extension cache TTL is 1 hour on top, so users see new announcements within an hour of merge (sooner on extension restart).
- No secrets, no auth, no infrastructure to maintain — by design.

### Alternative fetch URL (if we ever need it)

Raw GitHub serves the file with `Content-Type: text/plain` and has [documented occasional caching hiccups](https://github.com/orgs/community/discussions/169198). For our volume that's been a non-issue, but if we ever do hit problems the lowest-cost swap is jsDelivr, which is a CDN purpose-built for fronting GitHub repos:

```
https://cdn.jsdelivr.net/gh/rocketride-org/announcements@main/announcements.json
```

jsDelivr fixes the Content-Type (serves `application/json` correctly), offers a stable global CDN, and supports `@branch`, `@tag`, and `@commit-sha` pinning syntax. The swap is a one-line change in the extension fetch URL. Documenting it here as a known escape hatch.
