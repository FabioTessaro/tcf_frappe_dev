# 31 · Generated artifacts

## Purpose

Everything that is derived from a single source of truth, who generates it and where it goes.

## Catalogue

| Artifact | Source of truth | Generator | Output |
|---|---|---|---|
| API types | `<feature>/schemas.py` (pydantic) | Schema exporter (core tooling) | `<app>/frontend/features/<feature>/api/<feature>.api.types.ts` (generated section) |
| Integration OpenAPI | `integration/v<N>.py` schemas + registry | Schema exporter | `<app>/docs/openapi/v<N>.json` and served at `/api/ext/v<N>/openapi.json` |
| Error catalog | `errors.py` files | Catalog exporter | `errors.catalog.json`, TS union of codes + param types, locale entries, `.po` entries |
| Role constants | `<core-app>.sdk.roles` and `<app>/public/roles.py` | Roles exporter | `shared/constants/roles.ts` |
| App registry | Frontend `manifest.ts` files | `discover-apps` Vite plugin | Virtual registry module |
| Icon union | Every `icons.json` | `emit-shared-assets` Vite plugin | Icon subset, `icon-names.d.ts`, `public/shared-assets/` |
| Desk/server strings | Python, JS, doctype JSON | `bench generate-pot-file` | `<app>/locale/main.pot` |
| Portal entry HTML | Vite build | `copy-index-html` Vite plugin | `<core-app>/www/portal.html` |

## Rules

- `CT-GEN-001` Generated files MUST NOT be edited by hand. Each MUST start with a header comment
  `GENERATED — do not edit; source: <path>; generator: <name>`.
- `CT-GEN-002` Generated files that are committed MUST be regenerated in CI and compared with
  `git diff --exit-code`; any difference fails CI.
- `CT-GEN-003` Build outputs (`<core-app>/public/frontend/`) MUST NOT be committed.
- `CT-GEN-004` Generators MUST be deterministic (stable ordering, no timestamps in content).
- `CT-GEN-005` Generators are run through the task runner (`just generate`) in every repository
  ([50-delivery/504-toolchain](../50-delivery/504-toolchain.md)).
