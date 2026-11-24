# 02 · Governance

## Purpose

How this guide is versioned, changed and how deviations are recorded.

## Rules

- `FND-GOV-001` This guide is the authoritative source of truth for the architecture. Code,
  READMEs and comments MUST NOT contradict it; when they do, the guide wins and the code is a
  defect.
- `FND-GOV-002` The guide is **versioned with semantic versioning**:
  - *major*: a MUST rule is added, removed or tightened in a way that makes conforming code
    non-conforming;
  - *minor*: new chapters, new SHOULD/MAY rules, PENDING sections resolved;
  - *patch*: wording, examples, fixes that change no rule.
- `FND-GOV-003` Every change to the guide MUST go through review like code and MUST update the
  version and the changelog at the bottom of this file.
- `FND-GOV-004` Deviating from a **SHOULD** rule MUST be recorded in an ADR stored in the
  deviating repository under `docs/adr/NNNN-<slug>.md`, citing the rule ID.
- `FND-GOV-005` A **MUST** rule cannot be deviated from by ADR. If it is wrong, change the guide
  first (major or minor version).
- `FND-GOV-006` The guide is **controlled documented information** (ISO 9001/EN 9100 §7.5,
  ISO 27001 §7.5). Its history MUST be kept in version control; released versions MUST be tagged.

## Defaults

- `FND-GOV-010` Proposals to change the guide SHOULD be written as an ADR in the repository that
  holds the guide, then applied to the guide in the same change.
- `FND-GOV-011` When a local solution (not covered by the guide) is reused by a second app, it
  SHOULD be proposed for inclusion in the guide.

## Extension points

- `FND-GOV-020` Repositories MAY add their own, stricter rules in a local `docs/` folder,
  provided they do not contradict this guide.

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-11-23 | First release: frontend guide migrated, backend, contracts, security, testing, delivery, operations and compliance framework added |
| 1.1.0 | 2026-11-23 | Planned semantic search: new chapters 210-search and 35-search (Qdrant, audit stream as change feed, two-stage permissions, app/doctype filters, Desk record search on the same engine); `semantic_search` capability; `record_routes` in manifests (CT-REG-005); file text extraction (BE-FILE-012); search declarations per doctype; excluded vector technologies; Frappe Flow MUST NOT be used for search and SHOULD NOT be used elsewhere (DEL-TOOL-005) |
| 1.2.0 | 2026-11-23 | SEC-VULN-005 (pinning) scoped to platform releases and app repositories; new SEC-VULN-010: the development-environment repository MAY follow latest images and tools. BE-DATA-005 and TST-DATA-002 no longer mention a "reseed script" (the dev environment's `reseed.sh` refreshes the VS Code Server; it doesn't seed data). Markdown style fixes (code-block languages, playbook headings) |
| 1.3.0 | 2026-11-24 | GitHub replaces self-hosted Forgejo as the interim host: git hosting, GitHub Actions on GitHub-hosted runners, GitHub Container Registry, Renovate as a scheduled Actions job (504, DEL-REPO-005/006, 501, 503, reference deployment, new-feature-app playbook). New DEL-CI-007: actions only for plumbing, non-GitHub actions pinned to a commit SHA. Dependabot and GitHub-only pipeline features added to *Explicitly not used*. Open decision 7 reworded to the move to self-hosting. No existing repository was on Forgejo, so no conforming code becomes non-conforming |
| 1.4.0 | 2026-11-24 | FND-CONF-001 allows `Targets Platform Architecture Guide x.y` for repositories that do not conform yet; new FND-CONF-006 (open MUST rules listed in `docs/conformance.md`). DEL-TOOL-003 mechanism: `just sync-config` from a pinned `platform` commit, `just check-config` against drift (new standard recipes, level-1 step 2). Level-1 step 1: required apps not yet in `platform.lock` are checked out at `main`. DEL-CI-002: app trigger files call `platform`'s reusable app-CI workflow pinned to a commit SHA |
