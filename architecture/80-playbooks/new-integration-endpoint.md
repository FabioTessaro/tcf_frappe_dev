# Playbook · New integration endpoint

1. Confirm the consumer is an external system; the portal never uses integration endpoints
   (`FE-CLI-004`).
2. Add the function to `<feature>/integration/v<N>.py` with `integration_api(version=, scope=)`
   (`BE-API-010`, `BE-API-012`), reusing services and queries (`BE-API-017`).
3. Writes accept `Idempotency-Key` (`BE-API-013`); choose the `integration` rate tier (`SEC-RATE-001`).
4. Apply party scoping: the service account sees only its party's data (`SEC-MOD-002`).
5. `just generate` to update OpenAPI (`BE-API-014`); `just api-diff` must show no breaking change
   to an existing version (`BE-API-015`).
6. Tests in `test_integration_v<N>.py` (`TST-BE-*`).
7. Document the scope; grant it to clients through the onboarding runbook.
