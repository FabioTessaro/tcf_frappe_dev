# 109 · Caching, deploys and connectivity

## Rules

- `FE-CACHE-001` The portal MUST NOT use a service worker. It relies on normal browser caching.
- `FE-CACHE-002` Built files carry content hashes and are cached long-term; the portal entry page
  is served with `Cache-Control: no-store` so every deploy is picked up on the next load.
- `FE-CACHE-003` A failed lazy chunk load (stale tab after a deploy) MUST trigger exactly one page
  reload ([FE-SHELL-004](102-shell-and-routing.md)).
- `FE-CACHE-004` A `X-Build-Id` mismatch MUST show a non-blocking reload prompt
  ([CT-BOOT-004](../03-contracts/32-boot-data.md)).
- `FE-CACHE-005` Offline use is not supported; opening the portal offline shows the browser's
  error page. Losing the connection mid-session MUST show the `ConnectionBanner`, cleared when the
  connection returns.
