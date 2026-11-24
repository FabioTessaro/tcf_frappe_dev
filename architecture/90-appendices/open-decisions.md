# Open decisions

Areas marked **PENDING** in the guide. Until a decision is closed, implementers MUST respect the
constraints already written and MUST NOT implement beyond them ([00-how-to-read](../00-foundations/00-how-to-read.md)).
Closing a decision is a guide change (minor version).

| # | Topic | Where | Agreed so far | To decide |
|---|---|---|---|---|
| 1 | Management-system foundation app | [701](../70-compliance-framework/701-management-system-model.md), [20](../02-domain-foundations/20-core-primitives.md) | Shared primitives exist once (CMP-MS-001); core holds no business data | Confirm `<ims-app>` as a foundation app, its name and scope |
| 2 | Further tier-0 core primitives | [20](../02-domain-foundations/20-core-primitives.md) | Party model, Classification Level, Retention Class | Which other basic doctypes, if any, enter core |
| 3 | Workflows | [209](../20-backend/209-workflows.md) | Extend Frappe Workflow; editable by non-developers; any doctype; audited; e-signature on transitions; single code path | Designer UX, versioning and approval of workflow definitions, approver resolution, portal integration |
| 4 | Security baseline details | [301](../30-security-and-compliance/301-security-baseline.md) | Binding minimums SEC-BASE-001…010 | SSO/identity provider, exact session lifetimes, key management, MFA methods |
| 5 | Integration API authentication beyond API keys | [204](../20-backend/204-api-surfaces.md) | API key + secret per service account | Whether and when to add OAuth2 |
| 6 | Hosting of this guide | [500](../50-delivery/500-repositories.md) | Lives in the dev-environment repository until the `platform` repository exists | Move to `platform` and publish with MkDocs |
| 7 | Self-hosted git and CI | [500](../50-delivery/500-repositories.md), [504](../50-delivery/504-toolchain.md) | GitHub is the interim host (DEL-REPO-006); pipeline logic stays in `just` recipes and the CI image, no GitHub-only pipeline features (DEL-CI-002, DEL-CI-007), so a move replaces only trigger files, secrets and registry paths | Whether and when to self-host; target (Forgejo is the candidate); where Weblate (BE-I18N-005, FE-I18N-007) and the log stack run until then |
| 8 | Recovery objectives | [601](../60-operations/601-backup-and-restore.md) | Defaults RPO ≤ 15 min, RTO ≤ 8 h | Confirm through a business impact analysis |
| 9 | Semantic search: model and rollout | [210](../20-backend/210-search.md) | Qdrant, self-hosted embeddings, hybrid ranking, audit stream as change feed, two-stage permissions, app/doctype filters, keyword fallback, same engine for Desk record search | Embedding model (candidate BGE-M3), hardware for bulk embedding (CPU vs GPU), chunking of long documents, rollout timing |
| 10 | Semantic search: export-controlled data | [210](../20-backend/210-search.md) | BE-SRCH-051 default | Separate restricted collection or exclusion from semantic search |
