# Playbook · New feature (vertical slice)

**Backend**

1. Add the module to `modules.txt` and create `<app>/<feature>/` (`BE-STR-001`).
2. Doctypes in `doctype/` with explicit role permissions (`SEC-MOD-001`); declare default
   classification, retention class and PII inventory in `constants.py` (`DOM-CLS-001`,
   `SEC-REC-001`, `SEC-PRIV-001`); decide audit exclusions, if any, with reasons (`SEC-AUD-002`).
3. Row rules and party scoping in `permissions.py` (`SEC-MOD-002`, `SEC-MOD-004`).
4. Schemas in `schemas.py` (`BE-LAY-005`), error codes in `errors.py` (`CT-ERR-002`).
5. Business logic in `service.py`, reads in `queries.py` (`BE-LAY-*`), whitelisted functions in
   `api.py` with `portal_api` and a rate tier (`BE-SDK-002`, `SEC-RATE-001`).
6. File policies in `files.py` if the feature stores files (`BE-FILE-005`).
7. Jobs, events, realtime as needed (`BE-ASYNC-*`, `CT-RT-*`).
8. Seeds in `seed.py` (`BE-DATA-005`); tests `test_api.py`, `test_service.py`,
   `test_permissions.py` (`TST-BE-*`).

**Frontend**

9. Create `frontend/features/<feature>/` with the slice layout (`FE-STR-002`).
10. `just generate` to produce API types and error translations (`CT-GEN-005`).
11. `api/` module using the client (`FE-STR-008`, `FE-CLI-001`), composables, stores, components,
    views, routes with roles (`FE-SHELL-001`), locales in every language (`FE-I18N-004`).
12. Unit tests next to units; integration tests for non-trivial flows.

**Finish**

13. `just ci` green locally; pull request citing rule IDs (`TST-STR-002`, `DEL-REL-001`).
