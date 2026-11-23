# 405 · Test data and environments

## Rules

- `TST-DATA-001` Frontend fixtures (users, roles, parties, app lists, documents) live in
  `tests/mocks/fixtures/` and are shared by unit and integration tests.
- `TST-DATA-002` Backend and e2e data come from feature seeds ([BE-DATA-005](../20-backend/206-data-lifecycle.md))
  and `sdk.testing` factories; seeds are the single source of synthetic data for development
  sites, test sites and e2e tests.
- `TST-DATA-003` All test data MUST be synthetic ([BE-DATA-006](../20-backend/206-data-lifecycle.md)).
- `TST-DATA-004` E2E data is seeded on a dedicated test site and reset between runs.
- `TST-DATA-005` Two reference site profiles exist: **minimal** and **full**
  ([TST-BE-001](402-backend-tests.md)).
