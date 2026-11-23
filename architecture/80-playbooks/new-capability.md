# Playbook · New capability

1. Confirm the need: a consumer must work with and without the provider (`SYS-DEP-010`).
2. In `<core-app>.sdk.capabilities`: define the Protocol, the pydantic models and the fallback with
   documented behaviour (`DOM-CAP-001`, `DOM-CAP-002`, `DOM-CAP-005`). Bump the sdk minor version.
3. Add the capability to the catalogue in
   [22-capabilities](../02-domain-foundations/22-capabilities.md) (guide minor version).
4. Provider app: implement it under `<app>/public/` and register it in `provides_capabilities`.
5. Consumer: call `capability(name)`; never check installed apps (`DOM-CAP-003`).
6. Tests: consumer with fallback (minimal site) and with a fake provider (`DOM-CAP-006`,
   `TST-BE-002`); provider against the Protocol.
