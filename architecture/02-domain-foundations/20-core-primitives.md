# 20 · Core primitives

## Purpose

What the core app may own on the backend, so it stays a lean, business-agnostic platform.

## Rules

- `DOM-CORE-001` Core MUST NOT contain business data or business processes (no leave requests,
  orders, non-conformances, items, ...).
- `DOM-CORE-002` Core MAY contain only:
  1. **platform doctypes**: Audit Event, audit checkpoints, e-signature records, Signature
     Meaning, file policy settings, Retention Class, Legal Hold, disposition records,
     Classification Level, Security Incident, Core Settings, integration clients and webhook
     deliveries, capability configuration, Management System (the list of management systems
     used to tag shared-primitive records, [CMP-MS-002](../70-compliance-framework/701-management-system-model.md));
  2. **tier-0 business-agnostic primitives** listed in the table below.
- `DOM-CORE-003` Adding a doctype to the tier-0 table MUST be done by changing this guide
  (minor version), not by an ADR.
- `DOM-CORE-004` Tier-0 primitives MUST be generic and extensible by data (types, roles,
  identifiers as records), never by hard-coded enums of business meaning.

## Tier-0 primitives (current list)

| Primitive | Chapter | Status |
|---|---|---|
| Party, Party Type, Party Role, Party Member, Party Identifier, Identifier Type | [21-party-model](21-party-model.md) | Decided |
| Classification Level | [23-classification](23-classification.md) | Decided |
| Retention Class | [30-security-and-compliance/304-records-management](../30-security-and-compliance/304-records-management.md) | Decided |
| Further basic doctypes (e.g. units of measure, currencies, countries usage) | — | **PENDING**: to be decided; do not add without updating this table |

Frappe's own doctypes (User, Role, Contact, Address, Country, Currency, File, ...) are reused,
not duplicated.

## Defaults

- `DOM-CORE-010` Business primitives shared by several feature apps but not business-agnostic
  SHOULD live in a foundation app (e.g. `<ims-app>`), not in core.
