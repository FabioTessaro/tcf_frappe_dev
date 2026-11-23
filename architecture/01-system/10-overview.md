# 10 · System overview

## Purpose

The shape of the whole platform and the principles every other chapter derives from.

## The platform as a blank canvas

The platform is a **blank canvas**: core provides security, records, audit, files, parties,
capabilities and the portal shell; feature apps (QMS, HR, PLM, ERP, MES, ...) are added over
time and **progressively cover the target norms** listed in
[70-compliance-framework/700-norms-register](../70-compliance-framework/700-norms-register.md).

```
                ┌─────────────────────── one Frappe site ───────────────────────┐
 Browser ──────►│  Portal (Vue, served by <core-app>)   Desk (Frappe)   Website  │
                │        │ session + CSRF                    │            (<site-app>)
                │        ▼                                   ▼               │   │
                │  Portal API · Integration API · Guest API (site only)      │   │
                │        │                                                   │   │
                │  <core-app>  ◄── sdk ── <feature-app> ... <feature-app>    │   │
                │   (primitives, Party, capabilities, audit, files, records) │   │
                └──────┬───────────────┬──────────────────┬──────────────────┘
                       ▼               ▼                  ▼
                    MariaDB          Redis        S3-compatible object store
```

## Principles

- `SYS-PRIN-001` **Frontend independence.** Feature app frontends MUST NOT import each other;
  they depend only on the core frontend sdk and shared layer.
- `SYS-PRIN-002` **Declared backend dependencies.** Backend dependencies between apps are allowed
  but MUST be declared and follow the tiers in [11-app-kinds-and-dependencies](11-app-kinds-and-dependencies.md).
- `SYS-PRIN-003` **Vertical slices.** A feature is one frontend feature folder plus one backend
  Frappe module with the same name. Deleting a feature means deleting those two folders and
  their registrations.
- `SYS-PRIN-004` **Public surfaces only.** Code outside a unit imports only its public surface
  (frontend `index.ts`, backend `<app>.public`, the sdks).
- `SYS-PRIN-005` **Server-side security.** All access control is enforced on the server
  (permissions, party scoping, classification). Frontend checks are UX only.
- `SYS-PRIN-006` **One source of truth per concern** (roles, error codes, strings, settings,
  versions, icons). Derived artifacts are generated and checked in CI, never edited by hand.
- `SYS-PRIN-007` **Enforced, not conventional.** Every rule SHOULD have an automated check; rules
  without one are listed for manual review.
- `SYS-PRIN-008` **Compliance by design.** Audit, records management, privacy and classification
  are platform services that every app uses, not per-app inventions.
- `SYS-PRIN-009` **No third-party runtime dependencies** for fonts, icons or scripts in the
  portal; everything is self-hosted.
- `SYS-PRIN-010` **Single site per deployment.** One Frappe site per environment; no multi-tenancy.

## Compliance links

ISO 27001 A.8.27 (secure system architecture), EN 9100 §8.3.
