# 22 · Capabilities

## Purpose

Let apps use functionality provided by other apps **without depending on them**: soft (tier-1)
dependencies with a fallback.

## Mechanism

1. Core defines a capability in `<core-app>.sdk.capabilities`: a name, a Python `Protocol`, the
   pydantic models it exchanges, and a **fallback implementation**.
2. A provider app registers an implementation in `hooks.py`:
   `provides_capabilities = {"<capability>": "<app>.public.<module>.<Class>"}`.
3. A consumer calls `capability("<capability>")` and receives the provider, or the fallback.
4. The active capabilities are published in boot data so the portal can adapt its UI
   ([03-contracts/32-boot-data](../03-contracts/32-boot-data.md)).

## Rules

- `DOM-CAP-001` Capabilities MUST be defined only in the core sdk. Defining a new capability is a
  change to the sdk (minor sdk version).
- `DOM-CAP-002` Every capability MUST ship a fallback whose behaviour is documented
  (empty result, "not available" status, or a minimal implementation).
- `DOM-CAP-003` Consumers MUST NOT check whether a specific app is installed to decide behaviour;
  they MUST use the capability.
- `DOM-CAP-004` At most one provider per capability MAY be active. Two installed providers MUST
  make the site fail its startup check unless a provider is selected in Core Settings.
- `DOM-CAP-005` Capability inputs and outputs MUST be pydantic models (no doctype objects cross
  the boundary).
- `DOM-CAP-006` Consumers MUST be tested against the fallback (minimal site) and against a fake
  provider.

## Defined capabilities (catalogue)

| Capability | Purpose | Fallback |
|---|---|---|
| `party_screening` | Sanctions/restricted-party screening of a Party | Status "not screened" |
| `competence_registry` | Query qualifications/competences of a user or person | "unknown" (no qualifications) |
| `approver_resolver` | Resolve approvers for a document (e.g. reporting line) | Users holding a configured role |
| `document_control` | Link records to controlled documents and their revisions | Not available |
| `virus_scanner` | Scan a stored object | Not available ⇒ policies requiring a scan block access |

New capabilities are added to this table with the sdk change.

## Extension points

- `DOM-CAP-020` Apps MAY propose new capabilities; the proposal is an sdk change plus an update of
  this catalogue.
