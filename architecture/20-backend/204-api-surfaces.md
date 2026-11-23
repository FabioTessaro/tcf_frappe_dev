# 204 · API surfaces and versioning

## Purpose

The three API surfaces, their authentication and their stability promises.

| Surface | Code | Auth | Consumers | Stability |
|---|---|---|---|---|
| **Portal API** | `<feature>/api.py` | Session cookie + CSRF | The portal | Additive by default; breaking change ⇒ `<fn>_v2` with deprecation |
| **Integration API** | `<feature>/integration/v<N>.py`, served at `/api/ext/v<N>/<app>/<resource>` | Per-party service accounts (API key + secret) | Supplier/customer systems | Strict: major version in URL, months-long deprecation |
| **Guest API** | `<site-app>/api/public.py` only | None | Public website | Public-safe fields only |

## Portal API rules

- `BE-API-001` Portal API functions MUST use `portal_api` and MUST NOT allow guests.
- `BE-API-002` Additive changes (new optional parameter, new response field, new error code) are
  free. A breaking change MUST be introduced as a new function (`<name>_v2`); the old one is marked
  `deprecated_since="<platform version>"`, logs a warning when called, and is removed after one
  platform release.
- `BE-API-003` Method paths (`<app>.<feature>.api.<function>`) are a public contract; moving or
  renaming them is a breaking change.

## Integration API rules

- `BE-API-010` Integration endpoints MUST use `integration_api(version=, scope=)`; core's router
  maps stable public URLs to registered endpoints so Python modules can move.
- `BE-API-011` Authentication: one **service account** (Website User) per integration client,
  member of exactly one Party, with API key and secret. OAuth2 MAY be added later (pending).
- `BE-API-012` Every endpoint declares a **scope** (`<resource>:read|write`); clients are granted
  scopes explicitly.
- `BE-API-013` Writes MUST accept an `Idempotency-Key` header; repeated keys within 24 h return
  the original result.
- `BE-API-014` OpenAPI MUST be generated from schemas and served per version, filtered by the
  caller's scopes.
- `BE-API-015` A breaking change MUST create a new major version (`v<N+1>`); the previous version
  stays available for at least **12 months** after the new one is released and is announced to
  clients.
- `BE-API-016` Outbound **webhooks** MUST be signed (HMAC-SHA256 over body and timestamp), retried
  with backoff, and logged; clients can replay from the delivery log.
- `BE-API-017` Integration endpoints reuse `service.py` and `queries.py`; they MUST NOT duplicate
  business logic.
- `BE-API-018` A sandbox (the staging environment with synthetic data) SHOULD be offered to
  integration clients.

## Guest API rules

- `BE-API-020` Guest-reachable methods MUST exist only in `<site-app>/api/public.py`, use
  `guest_api`, return only public-safe fields of published records, be rate limited per IP and
  cache read-heavy results.
- `BE-API-021` Every change to the guest module MUST be reviewed as a security change.

## All surfaces

- `BE-API-030` Errors use the envelope ([03-contracts/30-error-catalog](../03-contracts/30-error-catalog.md)).
- `BE-API-031` Lists use the sdk list envelope.
- `BE-API-032` CI compares generated schemas and the error catalog against the last release:
  unflagged breaking portal changes and any breaking integration change fail CI.
- `BE-API-033` External (Website) users MUST NOT reach Frappe's generic `/api/resource` or
  `/api/method` outside allowlisted namespaces ([SEC-MOD-020](../30-security-and-compliance/300-security-model.md)).
