# 301 · Security baseline

## Status

The rules below are binding minimums derived from the mandatory norms (NIS2, ISO 27001/27002,
CRA, ISO 27701). The detailed design (SSO provider, exact session lifetimes, key management) is
**PENDING**; implement the minimums, nothing beyond them, until it is decided.

## Rules

- `SEC-BASE-001` Multi-factor authentication MUST be enforced for every System User and for every
  user holding an administrative role. External users SHOULD have MFA enabled; it MUST be possible
  to require it per Party Type.
- `SEC-BASE-002` Passwords follow Frappe's password policy set to strength score ≥ 3; login
  attempts are rate limited and lockout is enabled.
- `SEC-BASE-003` Sessions MUST expire after inactivity (default 8 h for System Users, 2 h for
  Website Users, configurable in Core Settings) and MUST be invalidated on password or role change.
- `SEC-BASE-004` All traffic MUST be served over TLS 1.2+ (TLS 1.3 preferred) by the reverse proxy;
  HSTS enabled; cookies `Secure`, `HttpOnly`, `SameSite=Lax` or stricter.
- `SEC-BASE-005` Data at rest MUST be encrypted: database volume, object-store volumes and backups.
- `SEC-BASE-006` Secrets MUST be stored only in `site_config.json`, Password fields or SOPS-encrypted
  files; never in images, repositories in clear text, logs or the frontend bundle.
- `SEC-BASE-007` Security headers MUST be set: Content-Security-Policy without third-party origins
  for the portal, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, `frame-ancestors` restricted.
- `SEC-BASE-008` Administrative access to servers MUST use SSH keys with MFA or a bastion; no shared
  accounts.
- `SEC-BASE-009` Clocks of all servers MUST be synchronised (NTP); timestamps are stored in UTC.
- `SEC-BASE-010` Least privilege: roles are granted per need; a periodic access review report MUST
  be available (users, roles, parties, last login).

## Compliance links

NIS2 Art. 21(2)(g)(h)(i)(j); ISO 27001 A.5.17, A.8.5, A.8.20–A.8.24; CRA Annex I.
