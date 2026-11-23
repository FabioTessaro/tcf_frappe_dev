# 210 · Search

## Status

**Planned.** Semantic search is not implemented yet; it will be added to the core app later. The
decisions below are **binding now** so that every app is built ready for it. Items still open are
listed in [90-appendices/open-decisions](../90-appendices/open-decisions.md) and MUST NOT be
implemented until decided.

Until semantic search ships, the same search API is served by **keyword search** (the fallback of
the `semantic_search` capability), so apps and the portal never change when it arrives.

## Purpose

One search across **every record the user may read**, in all apps, with optional filters by app
(e.g. only HR, only PLM) and by doctype (e.g. only Items, Leave Requests, Employees). Results match
by meaning (semantic) and by exact terms (keyword: part numbers, codes, IDs).

## Architecture

```text
MariaDB (source of truth)
  record change ──► Audit Event (same transaction, ordered, hash-chained)
                         │  indexer keeps a cursor on the audit stream
                         ▼
  indexer job: read current record from MariaDB → build text (declared fields, extracted file text)
               → embed (self-hosted model, dense + sparse) → upsert point in Qdrant
               (permission-only changes: payload update, no re-embedding)

Qdrant (disposable index)
  point = vectors + payload { app, doctype, name, chunk, party_ids, classification_rank,
                              owner, lang, modified, content_hash }   (no record text)

Query: embed query → Qdrant hybrid search WITH pre-filter from the user's context
       → candidates (doctype, name) → MariaDB permission-aware fetch (authoritative)
       → titles and snippets from MariaDB → audit reads of classified records → response
```

## Rules: technology

- `BE-SRCH-001` The semantic index MUST be **Qdrant**, self-hosted, reachable only from the
  platform's internal network, with API-key authentication and encryption at rest.
- `BE-SRCH-002` Embeddings MUST be computed by a **self-hosted** embedding service. Record content
  MUST NOT be sent to external embedding or AI APIs.
- `BE-SRCH-003` MariaDB native `VECTOR` columns, sqlite-vec and the Frappe Flow knowledge store
  MUST NOT be used for search ([50-delivery/504-toolchain](../50-delivery/504-toolchain.md)).
- `BE-SRCH-004` Search is exposed only through the `semantic_search` capability
  ([02-domain-foundations/22-capabilities](../02-domain-foundations/22-capabilities.md)); its
  fallback is keyword search. Apps MUST NOT call Qdrant or the embedding service directly.

## Rules: index and synchronisation

- `BE-SRCH-010` MariaDB is the source of truth. Qdrant is a **derived, disposable index**: a full
  rebuild from MariaDB MUST always be possible (`bench` command provided by core).
- `BE-SRCH-011` The indexer MUST consume the **audit stream** (Audit Events) as its change feed,
  keeping a persisted cursor of the last processed event. No separate outbox is created.
- `BE-SRCH-012` A doctype excluded from audit ([SEC-AUD-002](../30-security-and-compliance/302-audit.md))
  is **not searchable**.
- `BE-SRCH-013` The indexer reads the record's **current** state from MariaDB when processing an
  event; it never indexes data taken from the audit payload alone.
- `BE-SRCH-014` A content hash per point MUST prevent re-embedding unchanged text. Changes that only
  affect payload attributes (classification, party) MUST update the payload without re-embedding.
- `BE-SRCH-015` Deletion, disposition ([SEC-REC-003](../30-security-and-compliance/304-records-management.md))
  and GDPR erasure or anonymisation ([SEC-PRIV-004](../30-security-and-compliance/305-privacy.md))
  MUST remove or update the corresponding points.
- `BE-SRCH-016` A scheduled reconciliation job MUST compare MariaDB and Qdrant and repair drift.
- `BE-SRCH-017` Qdrant payloads MUST NOT contain record text, snippets or personal data beyond
  identifiers; they hold only what filtering and mapping back to MariaDB need.

## Rules: what is searchable (declared by every doctype, now)

- `BE-SRCH-020` Every doctype holding business data MUST declare in its module's `constants.py`
  its **search declaration**: whether it is searchable, the searchable fields (or a text template),
  the title field, and whether its attachments are searchable.
- `BE-SRCH-021` The fields declared searchable MUST be exactly the fields flagged
  `in_global_search` in the doctype JSON, so today's keyword search and tomorrow's semantic search
  index the same content.
- `BE-SRCH-022` Searchable attachments are indexed from the text extracted by the file pipeline
  ([BE-FILE-012](208-files.md)) and inherit the classification of the file.
- `BE-SRCH-023` Every searchable doctype MUST have a result route: a portal route declared in the
  owning app's manifest (`record_routes`, [CT-REG-005](../03-contracts/33-registry-manifests.md)),
  or the Desk form as fallback for System Users.

## Rules: querying and permissions

- `BE-SRCH-030` Search runs across all searchable doctypes the user may read. Optional filters by
  app and by doctype narrow it ([03-contracts/35-search](../03-contracts/35-search.md)).
- `BE-SRCH-031` **Stage 1 (pre-filter):** the Qdrant query MUST be filtered by the doctypes the user
  can read, the user's parties for party-scoped doctypes (external users), and the highest
  classification rank the user is authorised for, so forbidden records never influence ranking.
- `BE-SRCH-032` **Stage 2 (authoritative):** every candidate MUST be re-checked through the normal
  permission-aware MariaDB queries before it is returned. Qdrant is never the authority on access.
- `BE-SRCH-033` Titles and snippets MUST come from MariaDB (or extracted text in the object store)
  after stage 2, never from Qdrant.
- `BE-SRCH-034` Search reads of records whose classification requires read auditing MUST be audited
  ([DOM-CLS-004](../02-domain-foundations/23-classification.md)).
- `BE-SRCH-035` Search uses hybrid ranking: dense (meaning) and sparse (exact terms) results fused
  by rank. Exact identifiers (codes, part numbers, document names) MUST be findable.
- `BE-SRCH-036` The search API uses the `default` rate tier; indexing runs in background jobs on the
  long queue ([BE-ASYNC-001](207-async-and-cache.md)).

## Rules: Desk

Desk's awesomebar does two jobs: **navigation** (jump to doctypes, reports, pages; "New X"
commands) and **record search** (find documents). Only record search is in scope here.

- `BE-SRCH-040` Navigation in the awesomebar MUST keep Frappe's standard behaviour.
- `BE-SRCH-041` When semantic search is enabled, the awesomebar's record search SHOULD be served by
  the same `semantic_search` capability, index and API as the portal, through Frappe's
  whitelisted-method override hook (exact hook to be verified at implementation time), so Desk and
  portal return the same results for the same user.
- `BE-SRCH-042` Whatever engine serves Desk record search, it MUST apply the same two-stage
  permission rules (BE-SRCH-031, BE-SRCH-032) and read auditing (BE-SRCH-034).

## Defaults

- `BE-SRCH-050` The embedding model SHOULD be multilingual and produce dense and sparse vectors in
  one pass (candidate: BGE-M3), covering every language in the language registry.
- `BE-SRCH-051` Export-controlled records SHOULD be kept in a separate Qdrant collection with
  stricter access, or excluded from semantic search; the choice is an open decision.

## Compliance links

ISO 27001 A.5.15, A.8.3 (access restriction), A.8.11; GDPR Art. 17; ISO 15489 (disposition).
