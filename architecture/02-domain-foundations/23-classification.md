# 23 · Data classification

## Purpose

A single classification scheme for records and files that drives access, audit level, storage,
antivirus mode and retention.

## Model

**Classification Level** (core doctype, data): `code`, `label`, `rank` (higher = more sensitive),
`audit_reads` (bool), `allowed_storage_classes`, `requires_authorisation` (bool),
`restricted_search` (bool: indexed only in restricted search collections,
[BE-SRCH-100](../20-backend/210-search.md)), `default_retention_class`.

Recommended initial levels (data, adjustable by the deployment):

| Code | Rank | Example use |
|---|---|---|
| `public` | 0 | Website content, published job postings |
| `internal` | 10 | Ordinary internal records |
| `confidential` | 20 | HR records, contracts, prices |
| `customer_proprietary` | 30 | Customer drawings and specifications |
| `export_controlled` | 40 | Technology under EU dual-use control (`restricted_search` set) |

## Rules

- `DOM-CLS-001` Every doctype holding business data MUST declare a **default classification**
  (in its module's `constants.py` or doctype JSON property) and every File MUST carry a
  classification.
- `DOM-CLS-002` A record's classification MAY be raised by authorised users but MUST NOT be
  lowered below its doctype default.
- `DOM-CLS-003` Access to records whose level has `requires_authorisation` MUST additionally
  require an explicit user authorisation for that level (checked in permission hooks by the sdk).
- `DOM-CLS-004` Reads of records and files whose level has `audit_reads` MUST be audited
  ([30-security-and-compliance/302-audit](../30-security-and-compliance/302-audit.md)).
- `DOM-CLS-005` Files MUST be stored only in storage classes allowed for their classification.
- `DOM-CLS-006` Classification levels are referenced in code by `code` only.

## Extension points

- `DOM-CLS-020` The deployment MAY add levels (e.g. TISAX prototype protection) as data.

## Compliance links

ISO 27001 A.5.12–A.5.13 (classification, labelling), A.5.15 (access control); EU Reg. 2021/821
(dual-use technology, if applicable).
