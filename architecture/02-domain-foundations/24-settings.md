# 24 · Settings and configuration

## Purpose

Where configuration values live, decided by **who changes them**.

## Rules

| Who changes the value | Where it lives |
|---|---|
| Developers only; same in every environment | `constants.py` in the slice |
| Operations; differs per environment; may be secret | `site_config.json` (never committed) |
| Business administrators at runtime | One **Single doctype per app**: `<App> Settings` |

- `DOM-SET-001` Each app MUST have at most one Single settings doctype, named `<App> Settings`.
- `DOM-SET-002` Code MUST read settings only through the app's typed accessor
  (`<app>.public.settings()`), returning a pydantic model with defaults, cached and invalidated
  when the Single is saved. Direct `frappe.db.get_single_value` calls outside the accessor are
  forbidden.
- `DOM-SET-003` Secrets MUST live only in `site_config.json` or Password fields; never in code,
  constants, fixtures or the frontend bundle.
- `DOM-SET-004` Settings exposed to the portal MUST go through boot data or a settings endpoint
  that returns only portal-safe values.
- `DOM-SET-005` Feature flags are settings. A flag that hides a portal feature MUST also be
  enforced in the API layer.
- `DOM-SET-006` Changes to Settings doctypes MUST be audited (configuration change,
  [SEC-AUD-001](../30-security-and-compliance/302-audit.md)).

## Verification

Lint: forbid `get_single_value` outside `*/public/settings.py`; secret scanning (gitleaks) in CI.
