# 304 · Records management

## Purpose

Retention, legal hold and disposition of records and files, so the platform behaves as a records
system (ISO 15489 / ISO 16175).

## Model

- **Retention Class** (core doctype, data): `code`, `label`, `retention_period` (years/months, or
  "permanent"), `trigger` (creation, closure, release, end of product life, end of contract),
  `disposition` (destroy, anonymise, archive, review).
- **Legal Hold** (core doctype): scope (records, parties, doctypes, period), reason, owner; while
  active, disposition is suspended for the scope.

## Rules

- `SEC-REC-001` Every doctype holding business data and every file policy MUST declare a default
  retention class.
- `SEC-REC-002` A record is **declared** (becomes a controlled record) at a defined state
  (submit, release, approval, closure) declared by the doctype; after declaration its content MUST
  NOT change except through a new revision or an audited correction with reason.
- `SEC-REC-003` Disposition MUST run only through the records service: a scheduled job proposes
  disposition lists; a user with the `Records Manager` role approves them; execution is audited
  and leaves a disposition record (what, when, by whom, under which class), never the content.
- `SEC-REC-004` Records under legal hold MUST NOT be disposed of or modified.
- `SEC-REC-005` Deletion of declared records through Desk or API MUST be blocked; only disposition
  may remove them.
- `SEC-REC-006` Records MUST remain readable for their whole retention period: exports MUST be
  possible in open formats (PDF/A for documents, CSV/JSON for data) with their metadata, signatures
  and audit trail.
- `SEC-REC-007` Metadata required for every record: identifier, title, classification, retention
  class, owner, creation and declaration dates, relationships (revision of, attachment of).

## Compliance links

ISO 15489-1, ISO 16175; EN 9100 §7.5.3; ISO 27001 A.5.33; ISO 9001/14001/45001/50001 §7.5;
GDPR Art. 5(1)(e) (storage limitation).
