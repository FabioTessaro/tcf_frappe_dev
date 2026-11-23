# 00 · How to read this guide

## Purpose

Defines how every chapter is written and how its statements must be interpreted.

## Normative keywords

The keywords below are used as in RFC 2119 / RFC 8174, and only when written in capitals.

| Keyword | Meaning | Deviation |
|---|---|---|
| **MUST / MUST NOT / REQUIRED** | Boundary. Non-negotiable | Not allowed. Change the guide first (see [02-governance](02-governance.md)) |
| **SHOULD / SHOULD NOT / RECOMMENDED** | Default | Allowed only with an ADR citing the rule ID |
| **MAY / OPTIONAL** | Extension point; implementer's choice | Free. Stay consistent inside a repository |

Text without these keywords is explanatory. **Examples** (blocks or sentences starting with
"Example") are always non-normative.

## Rule IDs

Every normative statement has an ID: `<PREFIX>-<AREA>-<NNN>`, for example `BE-API-003`.

- IDs are **stable**: a rule that is removed keeps its ID as "withdrawn"; IDs are never reused.
- Tests, lint rules, ADRs, commit messages and the compliance traceability matrix reference
  rules by ID.

## Chapter template

Every chapter follows this order (sections may be omitted when empty):

1. **Purpose and scope**: what the chapter governs and what it does not.
2. **Rules**: MUST / MUST NOT.
3. **Defaults**: SHOULD.
4. **Extension points**: MAY.
5. **Rationale**: why.
6. **Verification**: which check enforces each rule (lint, test, CI step, or *manual review*).
7. **Examples**: non-normative.
8. **Compliance links**: norm clauses supported (feeds [70-compliance-framework](../70-compliance-framework/)).

## Placeholders

| Placeholder | Meaning |
|---|---|
| `<core-app>` | The core app. Its real name is chosen per deployment (`CORE_APP` in the dev bootstrap) |
| `<feature-app>` | Any feature app (HR, QMS, PLM, ERP, MES, ...) |
| `<site-app>` | The public website app |
| `<ims-app>` | The integrated-management-system foundation app (**PENDING**, see open decisions) |
| `<app>` | Any of the above |
| `<feature>` | A feature (vertical slice) inside an app |
| `<storage-class>` | A logical file storage class (see [20-backend/208-files](../20-backend/208-files.md)) |

## PENDING markers

A section marked **PENDING** documents constraints already agreed but not the full design.
Implementers MUST respect the written constraints and MUST NOT implement the rest until the
decision is closed in [90-appendices/open-decisions](../90-appendices/open-decisions.md).

## Verification

- `FND-READ-001` Rule IDs are unique across the guide. *Verified by:* docs lint in the
  `platform` repository CI (see [50-delivery/501-ci](../50-delivery/501-ci.md)).
