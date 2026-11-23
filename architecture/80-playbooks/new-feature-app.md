# Playbook · New feature app

1. Choose the app name (`SYS-APP-001`) and create the repository on Forgejo with the mandatory
   files (`DEL-REPO-004`), the shared tool configuration (`DEL-TOOL-003`) and the conformance
   statement (`FND-CONF-001`).
2. Create the Frappe app; set `required_apps` (≥ `<core-app>`) and `core_sdk_version`
   (`SYS-DEP-001`, `SYS-DEP-002`). Justify any other hard dependency in the README (`SYS-DEP-010`).
3. Create `<app>/public/` with `settings.py` and `roles.py` (`BE-INT-001`, `DOM-SET-002`);
   create `<App> Settings` only if business admins need runtime settings (`DOM-SET-001`).
4. Register in the launcher: `portal_apps` hook (`CT-REG-*`) and `frontend/manifest.ts` with the
   same id (`CT-REG-003`); list icons in `frontend/icons.json` (`FE-ICON-002`); add app-wide
   locales (`FE-I18N-004`) and optional app-scoped styles (`FE-STY-005`).
5. Create Party Types the app needs as fixtures (`DOM-PTY-004`) and profile doctypes if needed
   (`DOM-PTY-005`).
6. Build features with [new-feature](new-feature.md).
7. Add e2e specs for the main journeys (`TST-E2E-002`).
8. Add traceability rows for the norms the app covers (`CMP-REG-003`, `CMP-TRC-003`) and update the
   coverage roadmap.
9. Pass level-1 CI; open the `platform` pull request adding the app to `platform.lock`
   (`DEL-REPO-002`, `FND-CONF-005`).
