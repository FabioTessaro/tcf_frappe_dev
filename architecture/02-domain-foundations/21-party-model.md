# 21 · Party model

## Purpose

One generic model for every counterpart (supplier, customer, partner, applicant, authority, ...),
extensible by data and by apps, and the basis of party scoping for external users.

## Model

| Doctype (core) | Purpose | Key fields |
|---|---|---|
| **Party** | Any counterpart | `party_name`, `kind` (Organisation / Person), `status`, `parent_party` (groups, subsidiaries), `classification`, `screening_status`, `screening_checked_on`, `screening_list_version` |
| **Party Type** | Catalogue of kinds of party (data) | `code` (immutable, `^[a-z][a-z0-9_]*$`), `label`, `profile_doctype` (optional), `is_active` |
| **Party Role** (child of Party) | Which types a party has | `party_type`, `valid_from`, `valid_to` |
| **Party Identifier** (child of Party) | External identifiers | `identifier_type`, `value`, `valid_from`, `valid_to` |
| **Identifier Type** | Catalogue of identifier kinds (VAT, EORI, DUNS, NCAGE, tax code, ...) | `code`, `label`, `validation_pattern` (optional) |
| **Party Member** | Links a User to a Party | `user`, `party`, `member_role` (e.g. purchasing contact), `is_primary`, validity |

Contacts and addresses use Frappe's `Contact` and `Address` with Dynamic Links to Party.

**Profiles.** Data specific to a party type lives in a *profile doctype* owned by the app that
needs it, linked 1:1 to Party (e.g. `Supplier Profile` in a procurement app, `Customer Profile`
in a sales app).

## Rules

- `DOM-PTY-001` There MUST be exactly one Party doctype. Apps MUST NOT create their own
  counterpart master doctypes (no separate Supplier/Customer masters).
- `DOM-PTY-002` Party types MUST be data (Party Type records). Code MUST reference them only by
  `code`, never by label or name, and MUST NOT hard-code a closed list of types.
- `DOM-PTY-003` A Party MAY hold several roles at once; code MUST NOT assume a single type.
- `DOM-PTY-004` An app that needs a Party Type MUST create it idempotently (fixture or
  `after_app_install`) and MUST NOT delete it on uninstall if records use it.
- `DOM-PTY-005` Type-specific data MUST live in a profile doctype owned by the app, linked 1:1 to
  Party; Party itself MUST only hold fields common to every party.
- `DOM-PTY-006` Party scoping (see [30-security-and-compliance/300-security-model](../30-security-and-compliance/300-security-model.md))
  MUST be based on Party and Party Member only, independent of type, so new types inherit it.
- `DOM-PTY-007` Party Type `code` values are immutable once created.
- `DOM-PTY-008` Code MUST use the sdk helpers to query roles: `has_party_role(party, code)`,
  `parties_with_role(code)`, `user_parties(user)`.

## Defaults

- `DOM-PTY-010` Sanctions screening SHOULD be provided through the `party_screening` capability;
  the core fallback records "not screened". Business transactions with a party SHOULD check the
  screening status through the sdk.
- `DOM-PTY-011` Admins SHOULD be able to add Party Types and Identifier Types without a release.

## Extension points

- `DOM-PTY-020` Apps MAY add Party Types, profile doctypes, Identifier Types, Party Member roles.
- `DOM-PTY-021` Apps MAY add Custom Fields to Party only for data that is genuinely common to all
  parties of the deployment; otherwise use a profile.

## Verification

Backend contract test: no app defines a doctype with a Link to `User` used as party membership
other than Party Member; no hard-coded Party Type labels in code (lint rule searching
`party_type ==` with string literals not declared as constants from `<app>.public`).

## Compliance links

EN 9100 §8.4 (external providers), NIS2 Art. 21(2)(d) (supply-chain security), ISO 27001 A.5.19–A.5.22.
