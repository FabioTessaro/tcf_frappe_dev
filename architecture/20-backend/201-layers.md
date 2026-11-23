# 201 · Backend layers

## Responsibilities

| Layer | Does | Never does |
|---|---|---|
| `api.py` | HTTP boundary: `portal_api` decorator, input parsing and validation (pydantic), role gate, calls service or queries, returns schema models | Business rules, raw SQL, `ignore_permissions`, direct doctype manipulation beyond a single `get_doc` passed to a service |
| `integration/v<N>.py` | Same as `api.py` for the integration surface | Same as `api.py` |
| `service.py` | Commands: business operations, transactions, multi-document orchestration, audit events, enqueuing jobs, realtime publishing | Reading request state (`frappe.form_dict`, `frappe.request`) |
| `queries.py` | Read models for the UI: `frappe.qb` and `frappe.get_list` (permission-aware), pagination, filtering | Writes |
| Doctype controllers | Invariants of one document: `validate`, `before_submit`, computed fields | Cross-feature or cross-app calls, HTTP concerns, sending emails directly |
| `schemas.py` | pydantic models for inputs and outputs, params models | Logic |
| `permissions.py` | `has_permission`, `permission_query_conditions` registered in hooks | UX-only checks |
| `events.py` | doc_events handlers for this feature's doctypes; cache invalidation | Logic beyond delegating to services |
| `jobs.py` | Background and scheduled jobs | Calling `api.py` |

## Rules

- `BE-LAY-001` Only `api.py` and `integration/v<N>.py` may define whitelisted functions in feature
  apps (plus `<site-app>/api/public.py` for guests).
- `BE-LAY-002` Whitelisted functions MUST be thin: validate, authorise, delegate, shape.
- `BE-LAY-003` `service.py` and `queries.py` MUST be callable without a request (from jobs,
  patches, tests, other services).
- `BE-LAY-004` `frappe.get_all`, `ignore_permissions=True`, `frappe.db.sql` and
  `flags.ignore_permissions` MUST be accompanied by a `# perm-bypass: <reason>` comment and are
  forbidden in `api.py`.
- `BE-LAY-005` Input and output of every whitelisted function MUST be pydantic models from
  `schemas.py`; Frappe validates annotated arguments with pydantic and the sdk decorators
  enforce the output model.
- `BE-LAY-006` Apps MUST use the pydantic version pinned by Frappe and MUST NOT declare their own
  pydantic requirement.
- `BE-LAY-007` Jobs MUST call services, never whitelisted functions.

## Verification

Lint rules (custom ruff/AST check) for BE-LAY-001, 004, 007; backend contract test scanning all
whitelisted functions for the sdk decorator (BE-LAY-005, [BE-SDK-002](202-sdk.md)).
