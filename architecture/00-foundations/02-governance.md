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
|----|-------|-----------------------------------|
| 1.0.0 | 2026-11-23 | First release: frontend guide migrated, backend, contracts, security, testing, delivery, operations and compliance framework added |
| 1.1.0 | 2026-11-23 | Planned semantic search: new chapters 210-search and 35-search (Qdrant, audit stream as change feed, two-stage permissions, app/doctype filters, Desk record search on the same engine); `semantic_search` capability; `record_routes` in manifests (CT-REG-005); file text extraction (BE-FILE-012); search declarations per doctype; excluded vector technologies; Frappe Flow MUST NOT be used for search and SHOULD NOT be used elsewhere (DEL-TOOL-005) |
| 1.2.0 | 2026-11-23 | SEC-VULN-005 (pinning) scoped to platform releases and app repositories; new SEC-VULN-010: the development-environment repository MAY follow latest images and tools. BE-DATA-005 and TST-DATA-002 no longer mention a "reseed script" (the dev environment's `reseed.sh` refreshes the VS Code Server; it doesn't seed data). Markdown style fixes (code-block languages, playbook headings) |
| 1.3.0 | 2026-11-24 | GitHub replaces self-hosted Forgejo as the interim host: git hosting, GitHub Actions on GitHub-hosted runners, GitHub Container Registry, Renovate as a scheduled Actions job (504, DEL-REPO-005/006, 501, 503, reference deployment, new-feature-app playbook). New DEL-CI-007: actions only for plumbing, non-GitHub actions pinned to a commit SHA. Dependabot and GitHub-only pipeline features added to *Explicitly not used*. Open decision 7 reworded to the move to self-hosting. No existing repository was on Forgejo, so no conforming code becomes non-conforming |
| 1.4.0 | 2026-11-24 | FND-CONF-001 allows `Targets Platform Architecture Guide x.y` for repositories that do not conform yet; new FND-CONF-006 (open MUST rules listed in `docs/conformance.md`). DEL-TOOL-003 mechanism: `just sync-config` from a pinned `platform` commit, `just check-config` against drift (new standard recipes, level-1 step 2). Level-1 step 1: required apps not yet in `platform.lock` are checked out at `main`. DEL-CI-002: app trigger files call `platform`'s reusable app-CI workflow pinned to a commit SHA |
| 1.5.0 | 2026-11-24 | DEL-REPO-005: approvals depend on the number of maintainers — at least one approval by someone other than the author with two or more maintainers; a single maintainer may merge without approval after completing the self-review checklist. FND-CONF-003: the checklist is `.github/pull_request_template.md` from the shared configuration |
| 1.5.1 | 2026-11-25 | 501 level 2 step 1 matches the tooling: Renovate bumps `platform.lock` when an app pushes a release tag `vX.Y.Z`, on its scheduled run; untagged merges to `main` and pre-release tags are never proposed. Cross-repository changes are tested with pre-release tags (`vX.Y.Z-rc.N`) on the PR branches, because `platform.lock` holds only tags; release tags replace them before the `platform` pull request is merged. New-feature-app playbook step 9: tag the first release before adding the app to `platform.lock`. No rule changes |
| 1.6.0 | 2026-11-27 | Semantic search becomes multimodal with swappable models (ADR 0006 in the dev-environment repository): modalities `text` (BGE-M3, now decided) and `visual` (page images) described in a modality registry, one Qdrant collection per modality behind an alias, model upgrades as blue/green reindex (BE-SRCH-018, 019, 060–063); page check on every attachment page with configured routing, declaration hints that only add modalities (BE-SRCH-024, 025, 070–073); fusion of every modality plus exact-identifier lookup, rerank after stage 2, runtime degradation (BE-SRCH-035, 037, 038); Desk record search MUST use the same API once enabled, with Frappe's standard search as fallback (BE-SRCH-041, 043); file derivation pipeline with OCR and page features, derived objects follow erasure (BE-FILE-012–014, 022); search API reserves `filters`, adds `page`, enumerations are open sets (CT-SRCH-005, 006); model licence rule (DEL-TOOL-006); open decisions 9 and 11–16. Semantic search is not implemented and the new declaration keys are optional, so no conforming code becomes non-conforming |
| 1.7.0 | 2026-11-27 | Search options and restricted collections (ADR 0007 in the dev-environment repository). Open decision 10 closed: export-controlled content in restricted collections per modality on approved hosts, new Classification Level attribute `restricted_search` (BE-SRCH-100…103; BE-SRCH-051 withdrawn). Inference services internal, no content logging, no outbound traffic, `safetensors` only (BE-SRCH-006, 007). Keyword search while Qdrant is down or rebuilding (BE-SRCH-038); bounded refill after permission checks (BE-SRCH-039). Request `mode` (`smart`/`exact`, `smart` allowed by role), `include` record states, optional `max_pages` per request (omitted: no limit); results carry `thumbnail`, `state`, optional `highlights` and `more_matches`, `snippet` optional, facets approximate and no total count (CT-SRCH-009, 010); global search filters only by app, doctype and record state, reserved `filters` removed (CT-SRCH-006 withdrawn, CT-SRCH-011); search on submit; display is the client's choice (BE-SRCH-090…094, CT-SRCH-003, 007, 008). Query text not logged by default (BE-SRCH-095). DPIA required before semantic search is enabled in production (BE-SRCH-097, SEC-PRIV-006). OCR covers every registry language (BE-FILE-015). Search on the integration API kept as a future option (BE-SRCH-083). Search measurements, alerts and hardware reviews; Qdrant and inference services in health checks (BE-SRCH-096, SEC-OBS-007, 009–011). Semantic search is not implemented, so no conforming code becomes non-conforming |
| 1.8.0 | 2026-11-27 | Releases promote the tested image (ADR 0008 in the dev-environment repository): level 2 on `main` pushes the signed release candidate `main-<sha>` with a signed SBOM attestation (501 step 7, which said the version tag was pushed there); new DEL-REL-005 and release procedure in 502: a release verifies, re-scans and tags that candidate's digest, never rebuilds. Rollback procedure and deploy host contract in 503 (`backup.sh` prints the backup ID, `restore.sh <ID>`, both kept in the `platform` repository and copied to the host by each deploy; `current-version`, `rollback.env`); deploys use the compose file of the released version; new DEL-CD-007: a deploy changes nothing unless it can be rolled back, and does not start over an unfinished deploy. No platform has been deployed, so no conforming code becomes non-conforming |
