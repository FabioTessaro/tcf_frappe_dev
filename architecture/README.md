# Platform Architecture Guide

**Status:** authoritative · **Guide version:** 1.4.0 · **Applies to:** Frappe 16, Python 3.14, Node ≥ 24

This guide is the **single source of truth** for the architecture of the multi-app
Frappe platform: the core app, every feature app, the public website app, the
shared contracts between frontend and backend, security and compliance, testing,
delivery and operations.

It supersedes the former `Frappe Multi-app Vue Architecture.md` document, whose content it
includes (removed from the repository; available in git history).

---

## Read this first (humans and AI agents)

1. Read [00-foundations/00-how-to-read.md](00-foundations/00-how-to-read.md). It defines the
   keywords **MUST / MUST NOT / SHOULD / MAY**, rule IDs, and what is normative.
2. Read [00-foundations/03-conformance.md](00-foundations/03-conformance.md) before changing any
   repository: it says what "conforming" means and how deviations are recorded.
3. Check [90-appendices/open-decisions.md](90-appendices/open-decisions.md) before implementing
   anything in an area marked **PENDING**. Pending areas MUST NOT be implemented beyond the rules
   already written.
4. The tools named in [50-delivery/504-toolchain.md](50-delivery/504-toolchain.md) are
   **decided**. Do not substitute alternatives without an ADR.

### Rules for AI agents working on this platform

- Treat every **MUST / MUST NOT** as a hard boundary. Never work around one, even if a task
  seems to require it. Stop and ask instead.
- A **SHOULD** may only be deviated from with an ADR (see
  [00-foundations/02-governance.md](00-foundations/02-governance.md)). Propose the ADR; do not
  deviate silently.
- A **MAY** is freedom given to the implementer. Use judgement and stay consistent within a
  repository.
- If something is **not covered** by this guide, do not invent a platform-wide convention.
  Implement it in the smallest possible scope (one feature) and flag it as a candidate for the
  guide.
- Placeholders such as `<core-app>`, `<feature-app>`, `<feature>` are never literal names.
  Examples (HR, leave requests, expense claims) are **non-normative**.
- Cite rule IDs (e.g. `BE-API-003`) in commit messages, PR descriptions, ADRs and test names
  when a change implements or touches a rule.

---

## Structure

| Part | Folder | Governs |
|---|---|---|
| 0 | [00-foundations](00-foundations/) | How to read, glossary, governance, conformance |
| 1 | [01-system](01-system/) | App kinds, dependency tiers, access model, request lifecycle |
| 2 | [02-domain-foundations](02-domain-foundations/) | Core primitives, Party model, capabilities, classification, settings |
| 3 | [03-contracts](03-contracts/) | What frontend and backend agree on: errors, generated artifacts, boot data, registry, realtime, search API |
| 10 | [10-frontend](10-frontend/) | Vue portal: composition, structure, shell, sdk, client, styling, typography, fonts, icons, i18n, caching |
| 20 | [20-backend](20-backend/) | Python apps: slices, layers, sdk, inter-app rules, API surfaces, i18n, data, async, files, workflows, search |
| 30 | [30-security-and-compliance](30-security-and-compliance/) | Security model, baseline, audit, e-signatures, records, privacy, observability, rate limits, SBOM, incidents |
| 40 | [40-testing](40-testing/) | Strategy, frontend, backend, contract and e2e tests, test data |
| 50 | [50-delivery](50-delivery/) | Repositories, CI, releases, CD, toolchain |
| 60 | [60-operations](60-operations/) | Environments, backup and restore, runbooks |
| 70 | [70-compliance-framework](70-compliance-framework/) | Norms register, management-system model, traceability matrix, coverage roadmap |
| 80 | [80-playbooks](80-playbooks/) | Step-by-step procedures for common changes |
| 90 | [90-appendices](90-appendices/) | ADR template, reference deployment, open decisions |

## Recommended reading order

`00` → `01` → `02` → `03` → then `20` (backend) or `10` (frontend), depending on the task →
`30` → `40` → `50`. Playbooks (`80`) are the entry point for routine changes; each step links
back to the rules it applies.

## Book version (PDF and EPUB)

The guide can be built as a book: an A4 PDF for screens and printing, and an EPUB for Kindle
(via *Send to Kindle*) and other e-readers.

```bash
architecture/book/build.sh     # → architecture/book/dist/Platform-Architecture-Guide.{pdf,epub}
```

It needs only `python3` and Docker (pandoc and LaTeX run in the `pandoc/extra` image). The book
is generated from these Markdown files, which remain the source of truth; `dist/` is not
committed.

## Rule ID prefixes

| Prefix | Part | Prefix | Part |
|---|---|---|---|
| `FND` | Foundations | `SEC` | Security and compliance |
| `SYS` | System | `TST` | Testing |
| `DOM` | Domain foundations | `DEL` | Delivery |
| `CT` | Contracts | `OPS` | Operations |
| `FE` | Frontend | `CMP` | Compliance framework |
| `BE` | Backend | | |
