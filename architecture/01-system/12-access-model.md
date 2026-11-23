# 12 · Access model

## Purpose

Who can reach what, and the independent layers that enforce it. Details of the security model
are in [30-security-and-compliance/300-security-model](../30-security-and-compliance/300-security-model.md).

## User populations

| Population | Frappe user type | Desk | Portal | Scoping |
|---|---|---|---|---|
| Employees | System User | Allowed by role | Yes | Roles + document permissions |
| Supplier / customer contacts, applicants, other external parties | Website User | **Never** | Yes | Roles + **party scoping** |
| Integration service accounts | Website User (API key) | Never | No (integration API only) | Party scoping + scopes |
| Guests | — | No | Login pages only | Guest API only |

## Areas

| Area | Access |
|---|---|
| Public website | Public |
| Portal login and forgot-password | Public, guests only. Logged-in users are redirected to the launcher |
| App launcher (portal root) | Session required |
| Feature app pages | Session + role (and party type, when declared) allowed by the app's registration |
| Unknown portal routes | Guests → login; logged-in users → 404 |
| Desk (`/app`) | System Users only; owned by Frappe |

## Rules

- `SYS-ACC-001` Inside the portal only the auth routes are public. Every other route MUST be
  protected unless explicitly marked public.
- `SYS-ACC-002` Protection MUST be enforced in three independent layers: the portal page
  controller (server redirect), the router guard (UX), and the API layer (authoritative).
- `SYS-ACC-003` After login the user returns to the remembered destination, which MUST be
  validated as an internal portal path.
- `SYS-ACC-004` Guest boot data MUST contain nothing user-specific or sensitive. The built bundle
  is public and MUST NOT contain secrets.
- `SYS-ACC-005` External users MUST be Website Users and MUST only see records of parties they are
  members of ([02-domain-foundations/21-party-model](../02-domain-foundations/21-party-model.md)).
- `SYS-ACC-006` A central request guard MUST block Website Users from Frappe's generic endpoints
  outside an allowlist ([SEC-MOD-020](../30-security-and-compliance/300-security-model.md)).
- `SYS-ACC-007` The portal path MUST NOT be `/app` (owned by Desk).

## Verification

Integration tests `login-wall`, `role-guard`; backend tests on the portal page controller and
request guard; e2e journeys ([40-testing/404-e2e](../40-testing/404-e2e.md)).
