# 403 · Contract tests

## Frontend (`<core-app>/frontend/tests/contract/`)

| Test | Verifies |
|---|---|
| `manifests` | Every manifest valid: unique id, base path inside the portal, roles declared, navigation targets existing routes, `record_routes` target existing routes, icon names in the union, locale and style entries exist; id equals the backend hook id |
| `locales-parity` | Every language file in every location has exactly the default language's keys |
| `tokens` | Every token used by the Tailwind preset exists; every theme defines every token; apps override only app-themable tokens |
| `typography` | Language → script → typeface profiles for every device; every role resolves; font files exist |
| `icons` | Every listed icon exists in Material Symbols (all apps incl. website); generated types match the union |

## Backend (`<core-app>/tests/contract/`, run on the full site)

| Test | Verifies |
|---|---|
| `whitelist` | Every whitelisted method uses an sdk decorator; `allow_guest` only in `<site-app>.api.public` |
| `hooks_schema` | `portal_apps`, `provides_capabilities`, `core_sdk_version`, `portal_boot` entries validate |
| `error_catalog` | Codes unique; raised codes declared; declared codes translated |
| `permissions` | Every doctype defines permissions; party-scoped doctypes declare their Party field |
| `classification_retention_pii` | Every business doctype declares classification, retention class and PII inventory |
| `names` | App and module names do not collide with Frappe modules |
| `search_declarations` | Every business doctype has a search declaration; declared fields equal `in_global_search` fields; searchable doctypes are audited and have a result route (BE-SRCH-012, 020, 021, 023) |

## Platform (`platform` repository CI)

| Check | Verifies |
|---|---|
| Dependency graph | `required_apps` acyclic; sdk version ranges satisfied by the locked core |
| Generated artifacts | Regeneration produces no diff in any repository |
| API diff | Portal and integration schemas and the error catalog vs the last release ([BE-API-032](../20-backend/204-api-surfaces.md)) |
| Guide rule IDs | Unique; referenced IDs exist |

## Rules

- `TST-CT-001` Import boundaries are verified by linters (ESLint boundaries, import-linter), not by
  contract tests.
