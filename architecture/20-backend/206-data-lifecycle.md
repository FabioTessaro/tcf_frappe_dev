# 206 · Data lifecycle: patches, fixtures, seeds

## Rules

- `BE-DATA-001` Schema and data migrations MUST be Frappe patches listed in `patches.txt`, stored
  in `<feature>/patches/` and referenced as `<app>.<feature>.patches.<name>`.
- `BE-DATA-002` Patches MUST be idempotent and MUST NOT depend on optional apps unless guarded by
  capability or `meta.has_field` checks.
- `BE-DATA-003` Patches are irreversible; deployments MUST take a backup before `bench migrate`
  ([50-delivery/503-cd](../50-delivery/503-cd.md)).
- `BE-DATA-004` Fixtures MUST contain only **configuration**: roles, Party Types, Identifier
  Types, Classification Levels, Retention Classes, custom fields on Frappe doctypes, workflow
  definitions shipped as defaults, print formats. Business data MUST NOT be a fixture.
- `BE-DATA-005` Each feature MAY provide `seed.py` with synthetic data. Seeds MUST be idempotent,
  MUST refuse to run on a site without `developer_mode` or `allow_tests`, and are the single
  source of data for development, the reseed script and e2e tests.
- `BE-DATA-006` Seed data MUST be synthetic; real personal or customer data MUST NOT be used in
  dev, test or staging.

## Compliance links

ISO 27701 / GDPR (no real personal data in test), ISO 27001 A.8.33 (test information).
