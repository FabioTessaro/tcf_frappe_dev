# 305 · Privacy (GDPR, ISO 27701)

## Rules

- `SEC-PRIV-001` Every doctype MUST declare its **personal data inventory** in `constants.py`:
  which fields contain personal data, the category (identification, contact, employment, health,
  financial, ...), whether special categories are present, the purpose and the legal basis. A
  generator builds the platform-wide **record of processing** from these declarations.
- `SEC-PRIV-002` pydantic schemas returning personal data to the portal or integration API MUST
  mark those fields (`json_schema_extra={"pii": True}`) so exports and logs can treat them.
- `SEC-PRIV-003` Personal data MUST NOT be written to logs beyond user identifiers; log helpers
  redact marked fields.
- `SEC-PRIV-004` Data-subject requests (access, rectification, erasure, restriction, portability)
  MUST be supported by a core service that uses the inventory to locate data across apps; erasure
  is executed as anonymisation where retention obligations prevent deletion.
- `SEC-PRIV-005` Retention of personal data MUST follow the records-management service; the shortest
  period compatible with legal obligations applies.
- `SEC-PRIV-006` New features processing special categories of data or monitoring employees MUST
  include a DPIA reference in their app's `docs/`. Semantic search always requires one
  ([BE-SRCH-097](../20-backend/210-search.md)).
- `SEC-PRIV-007` Privacy defaults: data minimisation in schemas (return only needed fields),
  external users see only their own personal data and that of their party colleagues where
  required.

## Compliance links

GDPR Art. 5, 25, 30, 32, 35; ISO/IEC 27701; ISO 27001 A.5.34.
