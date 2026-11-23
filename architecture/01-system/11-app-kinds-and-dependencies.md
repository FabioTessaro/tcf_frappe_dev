# 11 · App kinds and dependencies

## Purpose

Which kinds of apps exist, what each may own, and how apps may depend on each other.

## App kinds

| Kind | Owns | Example |
|---|---|---|
| **Core** (`<core-app>`) | Portal shell, login, launcher, shared UI, design system, frontend and backend sdks, core primitives (Party, Audit Event, ...), platform services (files, audit, records, e-signature) | `<core-app>` |
| **Foundation app** | Business primitives shared by several feature apps | `<ims-app>` (**PENDING**) |
| **Feature app** | Business features, their doctypes, APIs, views | HR, QMS, PLM, ERP, MES |
| **Site app** | Public website, guest API | `<site-app>` |

## Rules: naming

- `SYS-APP-001` App names MUST match `^[a-z][a-z0-9_]*$` and MUST NOT collide with Frappe module
  names (in particular `core`, `desk`, `website`, `email`, `integrations`, `automation`).
  Module Def names are unique per site.
- `SYS-APP-002` The core app's name is configurable per deployment; documentation and code
  outside the core app MUST refer to it only through the sdk import path, never by hard-coding
  assumptions about its business meaning.

## Rules: dependency tiers

| Tier | When | Mechanism |
|---|---|---|
| **0 · core primitives** | Basic doctypes every app needs | Plain Link fields to core doctypes (every app requires core) |
| **1 · soft** | A feature works better with another app but MUST still work without it | Capabilities ([02-domain-foundations/22-capabilities](../02-domain-foundations/22-capabilities.md)) and provider-created Custom Fields |
| **2 · hard** | The feature makes no sense without the other app | `required_apps` + imports from `<other-app>.public` only |

- `SYS-DEP-001` Every app MUST declare `required_apps` containing at least `<core-app>`
  (the site app included).
- `SYS-DEP-002` Every app MUST declare the core sdk version range it supports
  (`core_sdk_version = ">=X.Y,<Z"` in `hooks.py`). Core MUST refuse installation outside the range
  and CI MUST check it.
- `SYS-DEP-003` The graph formed by `required_apps` MUST be acyclic.
- `SYS-DEP-004` Imports from another app MUST target only `<core-app>.sdk.*` or
  `<other-app>.public.*`, and only for apps listed in `required_apps`.
- `SYS-DEP-005` Tier-1 coupling code (doc_events on another app's doctypes, capability
  consumption with app-specific behaviour) MUST live in `<feature>/integrations/<other-app>.py`.
- `SYS-DEP-006` A Link field pointing to a doctype of a tier-1 (optional) app MUST NOT be part of
  a doctype's JSON. It MUST be created by the provider as a Custom Field in `after_app_install`
  and handled in `before_app_uninstall`
  (see [20-backend/203-inter-app](../20-backend/203-inter-app.md)).
- `SYS-DEP-007` Core MUST NOT depend on any feature app, foundation app or site app.
- `SYS-DEP-008` Frontends follow [SYS-PRIN-001](10-overview.md): backend dependencies never
  permit frontend imports between feature apps.

## Defaults

- `SYS-DEP-010` Prefer tier 1 over tier 2. A hard dependency SHOULD be justified in the app's
  README ("why this cannot degrade gracefully").
- `SYS-DEP-011` Only very basic, business-agnostic doctypes SHOULD enter core (see
  [02-domain-foundations/20-core-primitives](../02-domain-foundations/20-core-primitives.md)).

## Verification

| Rule | Check |
|---|---|
| SYS-APP-001 | Platform contract test: app and module names |
| SYS-DEP-002, 003 | `platform` CI: dependency-graph script |
| SYS-DEP-004 | import-linter contracts in each app (level-1 CI) |
| SYS-DEP-006 | Backend contract test: no Link to a non-required app's doctype in doctype JSON |
| SYS-DEP-007 | import-linter contract in core |

## Ownership matrix

| Concern | Core | Foundation / feature app | Site app |
|---|---|---|---|
| Vue shell, router, layouts, launcher | Owns | Registers into it, uses | Links to it |
| Login and session | Owns | Uses | Links to it |
| Shared components, design system, typography, fonts, icons | Owns | Uses; may add app-local parts and app-themable tokens | Own styles; links to core's shared assets |
| Backend sdk, capabilities registry, error catalog base | Owns | Uses, extends with own codes/capabilities | Uses |
| Party, Audit Event, file pipeline, records, e-signature | Owns | Uses | Uses where relevant |
| Business doctypes, APIs, permissions | Platform doctypes only | Owns | Public read-only endpoints |
| Translations | Common + own | App-wide + own features | Own pages |
| Tests | Runners, shared helpers, platform contracts | Own tests (run by core and CI) | Backend tests |
