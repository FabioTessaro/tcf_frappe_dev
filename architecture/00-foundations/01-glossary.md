# 01 · Glossary

| Term | Definition |
|---|---|
| **ADR** | Architecture Decision Record. A short document recording a decision or a deviation from a SHOULD rule. Template: [90-appendices/adr-template](../90-appendices/adr-template.md) |
| **App** | A Frappe app installed on the site |
| **Core app** (`<core-app>`) | The app that owns the Vue shell, login, launcher, shared UI, the backend sdk and core primitives. Holds no business data |
| **Feature app** (`<feature-app>`) | An app adding business capabilities (HR, QMS, PLM, ERP, MES, ...) |
| **Foundation app** | A feature app whose purpose is to provide shared business primitives to other apps (e.g. `<ims-app>`) |
| **Site app** (`<site-app>`) | The public website app. Not part of the Vue build |
| **Feature / slice** | A vertical unit of one app: a frontend feature folder plus a backend Frappe module with the same name |
| **Portal** | The single Vue application served by the core app under the portal path |
| **Desk** | Frappe's built-in admin UI (`/app`). Owned by Frappe |
| **sdk (frontend)** | `<core-app>/frontend/src/sdk`: the TypeScript contract feature apps use |
| **sdk (backend)** | `<core-app>.sdk`: the Python contract feature apps use |
| **Public surface** | The only modules other code may import from: a frontend feature's `index.ts`, a backend app's `<app>.public`, the sdks |
| **Capability** | A named interface defined in the core sdk, implemented (provided) by an app and consumed by others without importing the provider |
| **Dependency tier** | 0 = core primitive, 1 = soft (capability with fallback), 2 = hard (`required_apps`) |
| **Party** | Generic counterpart (organisation or person): supplier, customer, partner, applicant, authority, ... |
| **Party Type** | Data record defining a kind of party, identified by an immutable `code` |
| **Party scoping** | Restricting an external user to the records of the parties they are a member of |
| **Classification** | Label on records and files (Public, Internal, Confidential, Customer-proprietary, Export-controlled, ...) that drives access, audit, storage and retention |
| **Storage class** | Logical file store (e.g. `attachments`, `engineering`) mapped to a physical bucket by configuration |
| **Error code** | Stable, namespaced identifier of an error: `<app>.<feature>.<code>` |
| **Portal API** | Whitelisted methods called by the portal (session auth) |
| **Integration API** | Versioned endpoints for external systems of suppliers and customers |
| **Guest API** | The only unauthenticated methods, in `<site-app>.api.public` |
| **build_id** | Identifier of the deployed frontend/backend build, used to detect stale tabs |
| **trace_id** | Correlation identifier of one user action across requests, jobs, realtime and logs |
| **platform.lock** | File in the `platform` repository pinning Frappe and every app to exact versions |
| **Minimal site / full site** | Test site with only core plus the app under test and its hard dependencies / with every app |
| **Harmonized Structure (HS)** | The common clause structure (4–10) of ISO management-system standards, formerly Annex SL |
| **Website User / System User** | Frappe user types. Website Users never access Desk |
| **Modality** | A kind of searchable content handled by one embedding model, named by a stable id (`text`, `visual`; `image` reserved). See [20-backend/210-search](../20-backend/210-search.md) |
| **Modality registry** | Core configuration describing each modality: inference service, model and version, licence, Qdrant collection alias, enabled or not |
| **Page check** | The search routing step deciding, per attachment page, which modalities the page is indexed by |
| **Derived object** | An object generated from a stored file (extracted text, OCR, page features, previews) that inherits the file's classification, permissions and retention |
| **Restricted collection** | A search collection holding only content whose classification has `restricted_search` (e.g. export-controlled), on approved hosts and queried only for authorised users |
