# 302 · Audit trail

## Purpose

A complete, attributable, tamper-evident record of what happened, as a core platform service.
Frappe's Version doctype is kept for Desk history but is **not** the audit trail.

## What is captured

| Category | How |
|---|---|
| Data changes | Core `doc_events["*"]` (after_insert, on_update, on_submit, on_cancel, on_trash, after_rename) on audited doctypes, with field-level before/after |
| Business actions | `sdk.audit(event, doc, reason=…, **data)` in services (approve, release, export, transition, ...) |
| Reads of controlled data | Download route and sdk query helpers, for classifications with `audit_reads` |
| Security events | Login, logout, failed login, MFA events, password reset, API key creation/use, session expiry, permission denials |
| Configuration changes | Roles, permissions, user permissions, Party membership, workflows, settings, file policies, classification and retention data, integration clients, deploys |

## Record content

`event`, `category`, `user`, `impersonated_by`, `party` (external users), `doctype`, `docname`,
`changes` (field diff), `reason`, `channel` (portal / desk / integration / job / system), `ip`,
`user_agent`, `trace_id`, `timestamp` (UTC), `prev_hash`, `hash`.

## Rules

- `SEC-AUD-001` All categories above MUST be captured. Configuration changes are always audited.
- `SEC-AUD-002` Every doctype holding business data MUST be audited unless explicitly excluded in
  its `constants.py` with a reason (e.g. caches, transient queues). The audit stream is also the
  change feed of search, so an excluded doctype is not searchable
  ([BE-SRCH-011, BE-SRCH-012](../20-backend/210-search.md)).
- `SEC-AUD-003` Audit Events for data changes and business actions MUST be written in the **same
  database transaction** as the change.
- `SEC-AUD-004` Each Audit Event MUST store the hash of the previous event of its stream
  (hash chain, SHA-256 over canonical JSON).
- `SEC-AUD-005` A job MUST copy events to the `audit-archive` storage class, append-only (object
  lock/WORM where the store supports it), and write a **signed daily checkpoint** of the chain head.
- `SEC-AUD-006` A verification job MUST recompute the chain and checkpoints daily and raise a
  security incident on mismatch.
- `SEC-AUD-007` No role, including System Manager and Administrator, may update or delete Audit
  Events; the controller MUST raise on update and delete, and permissions MUST deny them.
- `SEC-AUD-008` Changes to records in a controlled state (released, approved, signed) MUST require
  a `reason`.
- `SEC-AUD-009` Audit retention follows the longest retention class of the records concerned and
  is never shorter than the retention class `audit` (default 10 years).
- `SEC-AUD-010` Auditing of employee activity MUST respect labour law on remote monitoring
  (e.g. Italian Workers' Statute art. 4): purposes MUST be documented, and audit data MUST NOT be
  used for performance monitoring.
- `SEC-AUD-011` Auditors MUST have read-only reports and exports (filter by record, user, period,
  category) without System Manager rights (role `Auditor`).

## Defaults

- `SEC-AUD-020` Anomaly alerts SHOULD exist for bulk downloads, access outside working hours to
  controlled data, and repeated permission denials.

## Compliance links

EN 9100 §7.5.3, §8.5.2; ISO 27001 A.8.15–A.8.17; ISO 15489; NIS2 Art. 21; ISO 27701 (accountability).
