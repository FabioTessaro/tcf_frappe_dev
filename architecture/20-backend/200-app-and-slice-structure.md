# 200 · Backend app and slice structure

## Purpose

How a Frappe app's Python package is organised: **one Frappe module per feature**, mirroring the
frontend feature folder.

## Layout

```text
<app>/                                   repository root
├── <app>/                               Python package
│   ├── __init__.py
│   ├── hooks.py                         wiring only
│   ├── modules.txt                      one line per feature module (+ "<App> Shared")
│   ├── patches.txt
│   ├── public/                          backend public surface for other apps (python package)
│   │   ├── __init__.py
│   │   ├── settings.py                  typed settings accessor
│   │   ├── roles.py                     role constants
│   │   └── <capability providers, read-only helpers other apps may use>
│   ├── <feature>/                       Frappe module = backend slice
│   │   ├── __init__.py
│   │   ├── api.py                       portal API (whitelisted)
│   │   ├── integration/                 optional: v1.py, v2.py (integration API)
│   │   ├── service.py                   commands, transactions, orchestration
│   │   ├── queries.py                   permission-aware reads
│   │   ├── schemas.py                   pydantic request/response models
│   │   ├── errors.py                    error codes
│   │   ├── permissions.py               has_permission / permission_query_conditions
│   │   ├── events.py                    doc_events handlers
│   │   ├── jobs.py                      background and scheduled jobs
│   │   ├── constants.py                 developer-only constants, default classification
│   │   ├── files.py                     file policies of this feature (if it stores files)
│   │   ├── seed.py                      seed data for dev and e2e
│   │   ├── integrations/                coupling with other apps: <other-app>.py
│   │   ├── patches/                     data/schema migrations of this feature
│   │   ├── doctype/                     doctypes of this feature
│   │   ├── report/                      optional
│   │   └── tests/                       test_api.py, test_service.py, test_permissions.py, ...
│   ├── <app>_shared/                    module for code/doctypes shared by ≥ 2 features of this app
│   └── locale/                          .po / .pot files (Desk and server strings)
├── frontend/                            see 10-frontend
├── docs/                                adr/, conformance.md, openapi/
├── pyproject.toml
└── README.md                            declares the guide version it conforms to
```

Example (non-normative): HR's leave requests are `hr/leave_requests/` (backend) and
`hr/frontend/features/leave-requests/` (frontend); the portal calls `hr.leave_requests.api.*`.

## Rules

- `BE-STR-001` Each feature MUST be one Frappe module listed in `modules.txt`, and its Python
  folder name MUST be the snake_case form of the frontend feature folder name.
- `BE-STR-002` A slice MUST contain only the files listed above (each optional except
  `__init__.py`); additional files require an ADR.
- `BE-STR-003` `hooks.py` MUST contain only wiring: registrations, doc_events, scheduler entries,
  permission hooks, fixtures, capability providers, portal app entries. No logic.
- `BE-STR-004` Code reused by ≥ 2 features of the same app MUST live in `<app>_shared/`; code
  reused by other apps MUST be exposed through `<app>.public`.
- `BE-STR-005` A feature MUST NOT import another feature's internal modules; it uses that
  feature's `service.py` or `queries.py` only, and only within the same app.
- `BE-STR-006` The site app follows the same structure; its guest endpoints live only in
  `<site-app>/api/public.py` ([204-api-surfaces](204-api-surfaces.md)).

## Extension points

- `BE-STR-020` Large slices MAY turn a file into a package of the same name (e.g. `service/`
  with `__init__.py` re-exporting the public functions).

## Verification

Structure contract test per app; import-linter contracts (BE-STR-004, 005).
