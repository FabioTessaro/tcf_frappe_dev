# 402 · Backend tests

## Per slice

| File | Covers |
|---|---|
| `test_api.py` | Guest rejection, role gate, party scoping, input validation (error codes and `fields`), response schema |
| `test_service.py` | Business rules, transactions, audit events emitted, jobs enqueued |
| `test_permissions.py` | Row-level rules per role and per party, classification authorisation |
| `test_integration_v<N>.py` | Scopes, idempotency, versioned schema (when the slice has integration endpoints) |
| `test_files.py` | Policy enforcement (type, size, antivirus mode) (when the slice stores files) |

## Core

The app-list method rejects guests and filters by roles, party types, capabilities; the session
and boot methods return only what the session may know; the portal page controller redirects guests
on non-login paths; the request guard blocks Website Users from generic endpoints; audit chain and
immutability; e-signature invalidation on content change; records disposition and legal hold.

## Site app

Every guest method returns only published, public-safe fields, honours rate limits and returns
cached data correctly.

## Rules

- `TST-BE-001` Backend tests MUST run on two sites in CI: a **minimal site** (core + the app + its
  hard dependencies) and a **full site** (all apps in `platform.lock`).
- `TST-BE-002` Consumers of capabilities MUST be tested with the fallback (minimal site) and with a
  fake provider (`sdk.testing`).
- `TST-BE-003` Tests MUST create their data through factories in `sdk.testing` and seeds; they MUST
  NOT depend on data left by other tests.
