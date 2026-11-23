# 30 · Error catalog and error envelope

## Purpose

One extensible catalog of error codes and one response shape, shared by backend, portal, Desk
and integration clients.

## Declaring codes

- Core provides the base `ErrorCatalog` in `<core-app>.sdk.errors`.
- Each slice declares its codes in `<feature>/errors.py`; codes shared by several features of an
  app live in `<app>/<app>_shared/errors.py`.
- Each code declares: identifier, HTTP status, a pydantic **params model**, and an English
  message template using those params.

Example (non-normative): namespace `hr.leave_requests`, code `overlapping_dates`, HTTP 409,
params `{start: date, end: date}`, template `"Overlaps an existing request from {start} to {end}"`.
Full code: `hr.leave_requests.overlapping_dates`.

## Core codes

| Code | HTTP | Use |
|---|---|---|
| `core.not_found` | 404 | Missing record or no right to know it exists |
| `core.forbidden` | 403 | Authenticated but not allowed |
| `core.session_expired` | 401 | No valid session |
| `core.conflict` | 409 | Concurrent modification (incl. Frappe timestamp mismatch), duplicates |
| `core.validation_failed` | 422 | Input invalid; details in `fields` |
| `core.rate_limited` | 429 | Rate tier exceeded; params `{retry_after: int}` |
| `core.internal` | 500 | Unexpected error |
| `core.field.<kind>` | — | Field-level codes generated from pydantic error types (`required`, `too_long`, `invalid_format`, ...) |

## Envelope

```json
{ "error": {
    "code": "hr.leave_requests.overlapping_dates",
    "params": { "start": "2026-12-01", "end": "2026-12-05" },
    "message": "Overlaps an existing request from 2026-12-01 to 2026-12-05",
    "fields": [ { "field": "from_date", "code": "core.field.required", "params": {} } ],
    "trace_id": "…" } }
```

`message` is rendered server-side in the user's language (for logs, Desk and clients without a
catalog). The portal displays its **own translation keyed by `code`**.

## Rules

- `CT-ERR-001` Every error returned by a portal, integration or guest endpoint MUST use the
  envelope and a catalog code. Frappe exceptions (`PermissionError`, `DoesNotExistError`,
  `DuplicateEntryError`, `LinkValidationError`, `TimestampMismatchError`, `ValidationError`)
  MUST be mapped to core codes by the sdk decorators.
- `CT-ERR-002` Codes MUST be namespaced `<app>.<feature>.<code>` (or `<app>.<code>` for
  app-wide, `core.*` for core). Segments match `^[a-z][a-z0-9_]*$`.
- `CT-ERR-003` Codes are **append-only**: a released code MUST NOT be renamed, reused or have its
  params changed incompatibly. Retire codes by marking them deprecated; remove only after one
  release cycle in which they are not raised.
- `CT-ERR-004` Code uniqueness MUST be checked at registry load (startup) and in CI.
- `CT-ERR-005` Raising code MUST use catalog errors (`raise LeaveErrors.OVERLAPPING_DATES(start=…, end=…)`);
  bare `frappe.throw("text")` is forbidden in feature code. Inside Desk-triggered controller
  logic the same catalog error renders its translated message, so one `raise` serves both Desk
  and the portal.
- `CT-ERR-006` The portal client MUST resolve unknown codes by falling back to the namespace's
  generic message, then to `core.internal`; it MUST NOT display raw codes.
- `CT-ERR-007` Stack traces and internal details MUST NOT be sent to non-System Users.
- `CT-ERR-008` Every code MUST have a translation in every supported language (portal locale and
  `.po`), generated from the catalog ([31-generated-artifacts](31-generated-artifacts.md)).

## Extension points

- `CT-ERR-020` Apps MAY add codes freely within their namespace; no core change is needed.

## Verification

Platform contract tests: uniqueness, every raised code declared, every declared code translated;
contract diff against the last release detects removed or changed codes (fails CI).
