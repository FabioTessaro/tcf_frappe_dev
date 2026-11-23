# 303 · Electronic signatures

## Purpose

One core service for signing records (approvals, releases, first article inspection reports,
non-conformance closure, training sign-off, ...).

## Rules

- `SEC-SIG-001` Signatures MUST be created only through `sdk.esign.sign(doc, meaning, reason=None)`.
- `SEC-SIG-002` Signing MUST require re-authentication at the moment of signing (password and, when
  enabled, MFA), even within a valid session.
- `SEC-SIG-003` Each signature MUST record: signer, full name at time of signing, **meaning**
  (code from the Signature Meaning catalogue: e.g. `reviewed`, `approved`, `released`,
  `verified`), timestamp (UTC), reason, and the SHA-256 of the record's canonical content
  (including file hashes of attachments in scope).
- `SEC-SIG-004` A signature MUST become invalid (and visibly so) if the signed content changes;
  re-signing is required.
- `SEC-SIG-005` Signatures MUST be displayed on the record and in its exports/prints with name,
  meaning and time.
- `SEC-SIG-006` Signature records are audit-protected like Audit Events ([SEC-AUD-007](302-audit.md)).
- `SEC-SIG-007` The legal level of in-platform signatures is an eIDAS **simple/advanced electronic
  signature**. Where a **qualified** signature or qualified timestamp is required, the sdk MUST
  delegate to a qualified trust service provider through a capability (`qualified_signature`).

## Extension points

- `SEC-SIG-020` Apps MAY add signature meanings as data.

## Compliance links

eIDAS Reg. (EU) 910/2014 as amended by 2024/1183; EN 9100 §8.6 (release), EN 9102, EN 9145;
ISO 27001 A.5.33.
