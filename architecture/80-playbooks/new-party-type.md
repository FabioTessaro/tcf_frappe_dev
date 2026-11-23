# Playbook · New Party Type

1. Choose an immutable `code` (`DOM-PTY-007`).
2. Administrators MAY create it in Desk without a release (`DOM-PTY-011`) when no code depends on it.
3. If code depends on it: ship it as a fixture or create it idempotently in `after_app_install` of
   the app that needs it (`DOM-PTY-004`); expose the code as a constant in `<app>.public`.
4. If type-specific data is needed: create a profile doctype in that app, linked 1:1 to Party
   (`DOM-PTY-005`).
5. If external users of this type use the portal: add the type to `party_types` of the relevant
   `portal_apps` entries (`CT-REG-*`) and verify party scoping applies (`DOM-PTY-006`).
