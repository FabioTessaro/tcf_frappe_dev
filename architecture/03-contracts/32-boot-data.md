# 32 · Boot data and build identity

## Purpose

What the portal page controller injects into the portal page, and how stale tabs are detected.

## Boot data content

| Key | Guests | Authenticated |
|---|---|---|
| `csrf_token` | Yes | Yes |
| `build_id` | Yes | Yes |
| `lang`, `available_languages` | Yes | Yes |
| `session` (user, full name, roles, user type) | No | Yes |
| `parties` (party IDs + types the user is member of) | No | Yes (external users) |
| `capabilities` (active capability names) | No | Yes |
| `settings` (portal-safe settings) | Minimal (branding) | Yes |
| `apps` (launcher list) | No | **No**: fetched from the app-list method |

## Rules

- `CT-BOOT-001` Boot data MUST be produced by `<core-app>.sdk.boot`, extendable by apps through a
  `portal_boot` hook that returns a pydantic model; apps' contributions are namespaced by app.
- `CT-BOOT-002` Guest boot data MUST contain only the guest column above.
- `CT-BOOT-003` `build_id` identifies the deployed platform build (platform version + commit). It
  MUST be included in boot data and in the `X-Build-Id` response header of every request.
- `CT-BOOT-004` When the client sees a response `X-Build-Id` different from its own, it MUST show a
  non-blocking "new version available — reload" prompt; on a failed lazy chunk load it MUST reload
  once (see [10-frontend/109-caching-and-deploys](../10-frontend/109-caching-and-deploys.md)).
- `CT-BOOT-005` Boot data MUST NOT be cached by HTTP caches; the portal page is served with
  `Cache-Control: no-store`.
