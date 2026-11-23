# 300 · Security model

## Purpose

The layered access-control model every app relies on.

## Layers (all mandatory)

1. **Doctype role permissions** (doctype JSON): the base.
2. **Row-level rules**: `permission_query_conditions` and `has_permission` in the slice's
   `permissions.py`; **party scoping** for external users; classification authorisation.
3. **API gate**: sdk decorators check session, roles, scopes and rate tier.
4. **Permission-aware queries**: `frappe.get_list` / `frappe.qb` with permission conditions.
5. **Request guard**: central allowlist for external users (below).

## Rules

- `SEC-MOD-001` Every doctype MUST define role permissions explicitly; no doctype may be readable by
  `All` or `Guest` unless it is deliberately public and served through the guest API.
- `SEC-MOD-002` Every doctype readable by external users MUST implement party scoping through the
  sdk (`sdk.party.scope_conditions(doctype, user)`), declaring which field links to Party.
- `SEC-MOD-003` External users MUST be Website Users. Granting Desk access (System User) to a party
  member is forbidden.
- `SEC-MOD-004` Classification authorisation ([DOM-CLS-003](../02-domain-foundations/23-classification.md))
  MUST be checked in `has_permission` via the sdk for doctypes that can hold such levels.
- `SEC-MOD-005` Frontend role checks are UX only; hiding a route or menu item is never security.
- `SEC-MOD-006` Permission bypasses follow [BE-LAY-004](../20-backend/201-layers.md).

## Request guard

- `SEC-MOD-020` Core MUST register a `before_request` guard that, for Website Users and integration
  service accounts, allows only: the portal page, the portal API namespaces of installed apps
  (`<app>.<feature>.api.*`), the integration router (service accounts only), file download routes,
  auth endpoints, and socket.io. Everything else — notably `/api/resource/*`,
  `/api/v2/document/*` and arbitrary `/api/method/*` — is rejected with `core.forbidden`.
- `SEC-MOD-021` The allowlist is derived from the sdk registries, not maintained by hand.

## Verification

Backend contract tests: permissions defined on every doctype; party-scoped doctypes declare their
Party field; request guard tests with a Website User hitting generic endpoints; e2e "supplier sees
only own records".

## Compliance links

ISO 27001 A.5.15–A.5.18, A.8.2–A.8.5; NIS2 Art. 21(2)(i) (access control).
