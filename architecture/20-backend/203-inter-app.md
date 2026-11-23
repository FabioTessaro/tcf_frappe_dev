# 203 · Inter-app backend rules

## Purpose

How apps interact on the backend under the dependency tiers of
[01-system/11-app-kinds-and-dependencies](../01-system/11-app-kinds-and-dependencies.md).

## Public surface

- `BE-INT-001` Each app that others may depend on MUST expose `<app>.public`: read-only helpers,
  settings accessor, role constants, capability providers, pydantic models. Everything else in the
  app is private.
- `BE-INT-002` `<app>.public` MUST NOT return doctype objects; it returns pydantic models or
  primitive values.

## Optional links (tier 1)

- `BE-INT-010` When feature X in app A should link to a doctype of optional app B, **app B**
  (the provider) MUST create the Link as a Custom Field on A's doctype in `after_app_install`
  (when A is installed) and in A's install path when B is already present (`after_app_install`
  in both directions, idempotent).
- `BE-INT-011` `before_app_uninstall` of the provider MUST either convert the field to a plain
  Data field preserving values, or refuse uninstall when data exists, according to the
  classification and retention of the data. It MUST NOT silently drop data.
- `BE-INT-012` Code reading such fields MUST tolerate their absence (`meta.has_field`) or go
  through a capability.

## Events across apps

- `BE-INT-020` doc_events registered by app A on app B's doctypes are allowed only in
  `<feature>/integrations/<b>.py` and only as tier-1 (they simply do not fire if B is absent).
- `BE-INT-030` Core MAY define **named hook points** (extension events) in the sdk; apps subscribe
  in `hooks.py`. This is preferred to doc_events on foreign doctypes when the event is business
  level (e.g. "party approved").

## Verification

import-linter (BE-INT-001); contract test: Custom Fields created by providers are removed or
converted on uninstall (minimal/full site install–uninstall cycle in CI).
