# 104 · Frappe client layer

## Purpose

`shared/frappe/`: everything that talks to Frappe. It imports nothing from features.

## Contents

| File | Responsibility |
|---|---|
| `client.ts` (+ test) | Request layer: attaches CSRF token and `X-Trace-Id`; reads `X-Build-Id`; parses the **error envelope** into a typed `AppError`; on `core.session_expired` sends the user to login; reports network failure to the connection banner |
| `call.ts` | The single entry for invoking whitelisted methods by name |
| `resource.ts` (+ test) | Reactive helpers for documents and lists with loading and error state, understanding the sdk list envelope (`items`, `total`, `cursor`/`page`) |
| `session.ts` | Reads boot data |
| `realtime.ts` | Socket connection and subscriptions ([03-contracts/34-realtime-events](../03-contracts/34-realtime-events.md)) |
| `errors.ts` | Maps error codes to translation keys with the fallback chain ([CT-ERR-006](../03-contracts/30-error-catalog.md)) |
| `permissions.ts` | Client-side document permission checks (UX only) |
| `types.ts`, `index.ts` | Types (documents, list envelope, `AppError`, generated `ErrorCode` union) and public surface |

## Rules

- `FE-CLI-001` All HTTP calls MUST go through `client.ts`. `fetch`/`axios` elsewhere is forbidden
  (ESLint `no-restricted-imports` / `no-restricted-globals`).
- `FE-CLI-002` Errors MUST be handled by code (`AppError.code`), never by parsing messages.
- `FE-CLI-003` Field errors (`fields`) MUST be mapped to form fields by the forms layer.
- `FE-CLI-004` Integration API endpoints MUST NOT be called by the portal; it uses the portal API.
- `FE-CLI-005` Reads MAY be retried with backoff on network failure or `core.rate_limited`
  (honouring `retry_after`); writes MUST NOT be retried automatically.
