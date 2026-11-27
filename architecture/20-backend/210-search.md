# 210 · Search

## Status

**Planned.** Semantic search is not implemented yet; it will be added to the core app later. The
decisions below are **binding now** so that every app is built ready for it. Items still open are
listed in [90-appendices/open-decisions](../90-appendices/open-decisions.md) (rows 9, 11–16) and MUST
NOT be implemented until decided.

Until semantic search ships, the same search API is served by **keyword search** (the fallback of
the `semantic_search` capability), so apps and the portal never change when it arrives.

## Purpose

One search across **every record the user may read**, in all apps, from both the portal and Desk,
with optional filters by app (e.g. only HR, only PLM) and by doctype (e.g. only Items, Leave
Requests, Employees). Results match by meaning (semantic), by exact terms (keyword: part numbers,
codes, IDs) and by what a page looks like (visual: drawings, scans, charts).

Content in scope: **record fields**, **text-rich documents** and **media-rich documents**
(attachments whose pages carry their meaning in drawings, images or layout). Photos and other
content kinds are future modalities (extension points below).

## Concepts

| Term | Meaning |
|---|---|
| **Modality** | A kind of content handled by one embedding model, named by a stable id: `text` (record fields and text pages), `visual` (page images). `image` (photos) is reserved |
| **Modality registry** | Core configuration listing each modality: inference service, model id and version, licence record, Qdrant collection alias, accepted inputs, enabled or not |
| **Derivation pipeline** | The file jobs that produce extracted text, OCR results and page features from a clean file ([208-files](208-files.md)) |
| **Page check** | The routing step that decides, per page, which modalities a page goes to |
| **Dense / sparse vector** | Dense: a "meaning fingerprint" (similar meaning, similar vector, even with different words). Sparse: a weighted keyword list (exact terms and codes) |

## Architecture

### Indexing

```text
MariaDB (source of truth)
  record change ──► Audit Event (same transaction, ordered, hash-chained)
                         │  dispatcher keeps a cursor on the audit stream
                         │  search declaration says searchable? no ─► skip
          ┌──────────────┴───────────────┐
   record fields                    searchable attachments (after the scan: clean)
          │                              │ derivation pipeline: type detection, text
          │                              │ extraction, OCR, page features (stored as
          │                              │ derived objects, BE-FILE-012)
          │                              ▼
          │                    page check (per page, CPU, configured rules)
          │                      → set of modality names per page
          │                        (+ modalities added by the declaration hint)
          ▼                              ▼
   "text" modality             one job per page and modality (content hash unchanged? skip)
          │                              │
          ▼                              ▼
   per-modality queues, live lane before backfill lane ─► inference service of the modality
          ▼
   Qdrant: one collection per modality (and model version), behind an alias per modality
     point = vectors + payload { app, doctype, name, file, chunk | page, party_ids,
                                 classification_rank, state, owner, lang, modified,
                                 content_hash, modality, model }   (no record text)
   restricted classifications (export-controlled) ─► "<modality>-restricted" collections
                                                      on approved hosts (BE-SRCH-100)

Nightly reconciliation (MariaDB ↔ Qdrant) and rebuilds run on the backfill lanes.
Permission-only changes: payload update in every collection, no re-embedding.
```

### Query

```text
portal search bar / Desk record search ──► <core-app>.search.api.search (one API)
 1. permission context: readable searchable doctypes ∩ requested, party_ids,
    highest classification rank, restricted access, record states from `include`,
    `smart` allowed for the user's roles? (cached per user); mode `exact` ─► keyword only
 2. in parallel, each with the stage-1 pre-filter:
      text modality: dense + sparse ─► text collection
      each other enabled modality  ─► its collection
      exact identifier lookup      ─► MariaDB
 3. weighted rank fusion ─► group chunks and pages by record (keep best passage)
 4. stage 2: permission-aware MariaDB check of every candidate
    (refill within the per-request budget; pages bounded by max_pages when given)
 5. rerank on text (record text, extracted text or OCR); hits without text keep their fused score
 6. titles, snippets, routes, page thumbnails ─► audit reads ─► response (query text not logged)
```

## Rules: technology

- `BE-SRCH-001` The semantic index MUST be **Qdrant**, self-hosted, reachable only from the
  platform's internal network, with API-key authentication and encryption at rest.
- `BE-SRCH-002` Embeddings and reranking MUST be computed by **self-hosted** inference services,
  one per modality. Record content MUST NOT be sent to external embedding or AI APIs.
- `BE-SRCH-003` MariaDB native `VECTOR` columns, sqlite-vec and the Frappe Flow knowledge store
  MUST NOT be used for search ([50-delivery/504-toolchain](../50-delivery/504-toolchain.md)).
- `BE-SRCH-004` Search is exposed only through the `semantic_search` capability
  ([02-domain-foundations/22-capabilities](../02-domain-foundations/22-capabilities.md)); its
  fallback is keyword search. Apps MUST NOT call Qdrant or the inference services directly.
- `BE-SRCH-005` Every model used by search (embedding, reranking, OCR, layout) MUST satisfy the
  model licence rule [DEL-TOOL-006](../50-delivery/504-toolchain.md); its licences (base model and
  any adapter or fine-tune) MUST be recorded in the modality registry.
- `BE-SRCH-006` Inference services receive record content in clear and MUST be protected like the
  database: reachable only from the platform's internal network and only by core's search backend,
  with authentication, and TLS whenever traffic leaves the host. Users and clients never call them.
- `BE-SRCH-007` Inference services MUST NOT log or persist request content (no payload logging, no
  disk cache) and MUST NOT make outbound connections at runtime (no telemetry, no model downloads).
  Model files are fetched at build time, pinned by checksum, and MUST be in the `safetensors`
  format (pickle-based formats can execute code when loaded).

## Rules: index and synchronisation

- `BE-SRCH-010` MariaDB is the source of truth. Qdrant is a **derived, disposable index**: a full
  rebuild from MariaDB and the object store MUST always be possible (`bench` command provided by
  core), per modality or for all.
- `BE-SRCH-011` The indexer MUST consume the **audit stream** (Audit Events) as its change feed,
  keeping a persisted cursor of the last processed event. No separate outbox is created, and apps
  do not enqueue records for indexing.
- `BE-SRCH-012` A doctype excluded from audit ([SEC-AUD-002](../30-security-and-compliance/302-audit.md))
  is **not searchable**.
- `BE-SRCH-013` The indexer reads the record's **current** state from MariaDB when processing an
  event; it never indexes data taken from the audit payload alone.
- `BE-SRCH-014` A content hash per point (text chunk or page) MUST prevent re-embedding unchanged
  content. Changes that only affect payload attributes (classification, party) MUST update the
  payload in every collection without re-embedding.
- `BE-SRCH-015` Deletion, disposition ([SEC-REC-003](../30-security-and-compliance/304-records-management.md))
  and GDPR erasure or anonymisation ([SEC-PRIV-004](../30-security-and-compliance/305-privacy.md))
  MUST remove or update the corresponding points in **every** collection, together with the derived
  objects of [BE-FILE-013](208-files.md).
- `BE-SRCH-016` A scheduled (nightly by default) reconciliation job MUST compare MariaDB and every
  Qdrant collection and repair drift, including records missed by the change feed.
- `BE-SRCH-017` Qdrant payloads MUST NOT contain record text, snippets or personal data beyond
  identifiers; they hold only what filtering and mapping back to MariaDB need, plus the modality
  and the model id and version that produced the vectors.
- `BE-SRCH-018` Indexing jobs MUST run on dedicated queues per modality, each with a **live** lane
  (changes from the audit stream) served before a **backfill** lane (reconciliation, rebuilds,
  model upgrades), so a backfill never delays fresh changes and a slow modality never blocks
  another.
- `BE-SRCH-019` A model upgrade is a reindex: the new model fills a **new** collection while the
  alias still points to the old one; the alias switches when the new collection is complete and the
  old one is then deleted. Vectors from different models MUST NOT be mixed in one collection.

## Rules: what is searchable (declared by every doctype, now)

- `BE-SRCH-020` Every doctype holding business data MUST declare in its module's `constants.py`
  its **search declaration**: whether it is searchable, the searchable fields (or a text template),
  the title field, and its attachment settings (BE-SRCH-024).
- `BE-SRCH-021` The fields declared searchable MUST be exactly the fields flagged
  `in_global_search` in the doctype JSON, so today's keyword search and tomorrow's semantic search
  index the same content. Record fields are indexed by the `text` modality only.
- `BE-SRCH-022` Searchable attachments are indexed from the derived objects of the file pipeline
  ([BE-FILE-012](208-files.md)) and inherit the classification of the file.
- `BE-SRCH-023` Every searchable doctype MUST have a result route: a portal route declared in the
  owning app's manifest (`record_routes`, [CT-REG-005](../03-contracts/33-registry-manifests.md)),
  or the Desk form as fallback for System Users.
- `BE-SRCH-024` Attachment settings are an **open, versioned structure** defined by core's
  declaration schema: a doctype-level default (which also covers Frappe's generic attachments) and
  optional per-field entries. Every key MUST be optional with a default, so a new key never
  invalidates existing declarations; unknown keys MUST fail validation. Adding a key is a core
  schema change (minor version).
- `BE-SRCH-025` The only routing key today is `routing`: `auto` (default; the page check decides)
  or a list of modality names that every page receives **in addition** to the page check's result
  (e.g. `["visual"]` for a drawings field). A hint MUST only add modalities, never remove the ones
  the page check selected, so a wrong declaration cannot drop content from search.

Example (non-normative) of an attachment declaration:

```python
SEARCH = {
    "searchable": True,
    "fields": ["item_name", "description"],
    "title_field": "item_name",
    "attachments": {
        "searchable": True,
        "default": {"routing": "auto"},  # generic attachments, sidebar
        "fields": {"drawing": {"routing": ["visual"]}},  # every page also to `visual`
    },
}
```

## Rules: querying and permissions

- `BE-SRCH-030` Search runs across all searchable doctypes the user may read. Optional filters by
  app and by doctype narrow it ([03-contracts/35-search](../03-contracts/35-search.md)). It is a
  global search: filtering by field values or dates is left to each doctype's list views.
- `BE-SRCH-031` **Stage 1 (pre-filter):** every Qdrant query MUST be filtered by the doctypes the
  user can read, the user's parties for party-scoped doctypes (external users), and the highest
  classification rank the user is authorised for, so forbidden records never influence ranking.
- `BE-SRCH-032` **Stage 2 (authoritative):** every candidate MUST be re-checked through the normal
  permission-aware MariaDB queries before it is returned or reranked. Qdrant is never the authority
  on access.
- `BE-SRCH-033` Titles and snippets MUST come from MariaDB (or derived text in the object store)
  after stage 2, never from Qdrant.
- `BE-SRCH-034` Search reads of records whose classification requires read auditing MUST be audited
  ([DOM-CLS-004](../02-domain-foundations/23-classification.md)).
- `BE-SRCH-035` Search uses hybrid ranking: the result lists of every enabled modality (for `text`:
  dense and sparse), plus an exact lookup of identifiers in MariaDB, fused by rank with configurable
  weights. Exact identifiers (codes, part numbers, document names) MUST be findable.
- `BE-SRCH-036` The search API uses the `default` rate tier; indexing runs in background jobs on
  the queues of BE-SRCH-018 ([BE-ASYNC-001](207-async-and-cache.md)).
- `BE-SRCH-037` Reranking, when enabled, MUST run after stage 2, on text read from MariaDB or
  derived objects. Candidates without text (visual-only pages without OCR text) keep their fused
  score.
- `BE-SRCH-038` If a modality's inference service is unavailable, the query MUST be answered with
  the remaining modalities; if the `text` modality or Qdrant is unavailable (including during a full
  rebuild), it MUST be answered by keyword search (`engine: keyword`). A search request never fails
  because a model or the index is down.
- `BE-SRCH-039` When stage 2 drops candidates, the server MUST fetch further candidates to fill the
  page, within a **per-request budget** (maximum refill rounds, candidates and time; configurable
  in core's search settings). When the budget is spent the page is returned with fewer items; the
  response MUST NOT say why, so it reveals nothing about records the user cannot read. The total
  results reachable through the cursor are bounded only by the request's optional `max_pages`
  ([CT-SRCH-008](../03-contracts/35-search.md)).

## Rules: Desk

Desk's awesomebar does two jobs: **navigation** (jump to doctypes, reports, pages; "New X"
commands) and **record search** (find documents). Only record search is in scope here.

- `BE-SRCH-040` Navigation in the awesomebar MUST keep Frappe's standard behaviour.
- `BE-SRCH-041` When semantic search is enabled, Desk MUST offer record search served by the same
  `semantic_search` capability, index and API as the portal, so Desk and portal return the same
  results for the same user. Serving the awesomebar's record search through Frappe's
  whitelisted-method override hook SHOULD be the way it is offered (exact hook to be verified at
  implementation time); otherwise a dedicated Desk search page.
- `BE-SRCH-042` Whatever engine serves Desk record search, it MUST apply the same two-stage
  permission rules (BE-SRCH-031, BE-SRCH-032) and read auditing (BE-SRCH-034).
- `BE-SRCH-043` While semantic search is not enabled (or not installed), Desk MUST keep Frappe's
  standard record search and the portal MUST be served by keyword search through the same API.

## Rules: modalities and models

- `BE-SRCH-060` Every modality MUST be described only in the **modality registry**: id, inference
  service, model id and version, licence record, collection alias, accepted inputs, enabled flag.
  Device, batch size, worker counts and endpoints are deployment configuration.
- `BE-SRCH-061` Code outside the registry and the inference adapters MUST refer to modalities by id,
  never to a model. Replacing a model MUST NOT require code changes outside them.
- `BE-SRCH-062` Indexing, routing and querying MUST handle any number of modalities. Two are active
  now: `text` and `visual`.
- `BE-SRCH-063` A disabled modality MUST degrade, not lose content: pages routed to `visual` while
  it is disabled are indexed by `text` from their extracted or OCR text.

## Rules: page check and routing

- `BE-SRCH-070` The page check MUST run for every page of every searchable attachment, whatever the
  declaration says, and MUST NOT need a GPU.
- `BE-SRCH-071` It decides from page features produced by the derivation pipeline (today: text
  coverage, image area, vector line density, OCR confidence; more MAY be added).
- `BE-SRCH-072` Routing rules (features and thresholds → set of modality ids) MUST be
  configuration, not code. A page matching no rule clearly MUST go to every candidate modality
  ("in doubt, both").
- `BE-SRCH-073` The page check is a replaceable component with a fixed output: for each page, the
  set of modality ids it goes to. A different implementation (e.g. a learned classifier) MUST keep
  this output.

## Rules: request options and results

- `BE-SRCH-090` The request `mode` selects the engine: `smart` (default; every enabled modality plus
  exact lookup) or `exact` (keyword search only). `exact` means exact: no typo tolerance, no
  synonyms.
- `BE-SRCH-091` Which users may use `smart` is configured by role in core's search settings
  (default: every System User; external parties such as trusted suppliers by granting a role).
  Other users are served keyword search (`engine: keyword`) whatever `mode` they send. This
  controls cost and policy; access to records is still enforced by both permission stages for
  every user.
- `BE-SRCH-092` Every searchable record is indexed whatever its state; the payload carries a
  **record state** (open set defined by core: `active`, `cancelled`, `superseded`). Core derives
  `cancelled` (docstatus 2) and `superseded` (amended by a newer record) for every doctype; apps MAY
  map further states through the search declaration (BE-SRCH-024). Only `active` records are
  returned unless the request's `include` asks for other states; the filter is applied in stage 1.
- `BE-SRCH-093` Child-table rows are indexed as part of their parent record; results always point
  to the parent.
- `BE-SRCH-094` A hit on an attachment page MUST carry the page number and SHOULD carry a
  `thumbnail` link of that page, served through the file download route
  ([BE-FILE-008](208-files.md)) so permission checks and read auditing apply. Whether and how a
  client shows it is the client's choice.
- `BE-SRCH-096` Search MUST expose the measurements and health checks of
  [SEC-OBS-009…011](../30-security-and-compliance/306-observability.md), because its fallbacks hide
  failures from users.
- `BE-SRCH-097` Semantic search processes personal data of every app, including special
  categories, through machine-learning models. A DPIA
  ([SEC-PRIV-006](../30-security-and-compliance/305-privacy.md), GDPR Art. 35) MUST be referenced in
  core's `docs/` before semantic search is enabled in production, and reviewed when a modality, a
  model or query logging (BE-SRCH-095) is added or changed.
- `BE-SRCH-095` **Query logs.** By default only metadata MAY be logged (user, time, mode, engine,
  result count, latency), never the query text. Logging query text (e.g. to tune quality) MUST be
  enabled by configuration, pseudonymised, kept at most 30 days by default, readable only by the
  search maintainers, listed in the record of processing
  ([SEC-PRIV-001](../30-security-and-compliance/305-privacy.md)), and checked against employee
  monitoring obligations before it is enabled
  ([SEC-PRIV-006](../30-security-and-compliance/305-privacy.md)).

## Rules: export-controlled data (restricted collections)

- `BE-SRCH-100` Records and files whose classification level has `restricted_search`
  ([23-classification](../02-domain-foundations/23-classification.md); set for
  `export_controlled`) MUST be indexed only in **restricted collections**, one per modality
  (`<modality>-restricted`), never in the normal collections.
- `BE-SRCH-101` Restricted collections, and the inference services that embed restricted content,
  MUST run on hosts approved for that data (location, administrative access limited to authorised
  staff). They SHOULD be a separate Qdrant instance and separate inference services; the modality
  registry describes them per modality.
- `BE-SRCH-102` Restricted collections MUST be queried only for users authorised for the level
  ([DOM-CLS-003](../02-domain-foundations/23-classification.md)); for every other user they are not
  queried at all. Their results are fused like any other list.
- `BE-SRCH-103` Every other rule of this chapter (stage 2, read auditing, erasure, reconciliation,
  model upgrades, fallback) applies to restricted collections unchanged.

## Defaults

- `BE-SRCH-050` The `text` modality SHOULD use **BGE-M3** (multilingual, dense and sparse vectors in
  one pass), covering every language in the language registry.
- `BE-SRCH-051` *Withdrawn in 1.7.0; replaced by BE-SRCH-100…103 (restricted collections).*
- `BE-SRCH-052` The `visual` modality SHOULD use a late-interaction page-image model (candidate: the
  ColQwen family), stored as multi-vectors; the model is open decision 11.
- `BE-SRCH-053` Reranking SHOULD use a multilingual text cross-encoder (candidate:
  bge-reranker-v2-m3); the model is open decision 12.
- `BE-SRCH-054` Initial routing rules SHOULD favour recall: when the features disagree, a page goes
  to both `text` and `visual`.

## Extension points

- `BE-SRCH-080` New modalities (e.g. `image` for photos) MAY be added as a registry entry, a
  collection and routing rules, without changes to apps or to the search API.
- `BE-SRCH-081` New page features, routing rules and declaration keys MAY be added through core
  (BE-SRCH-024, BE-SRCH-071).
- `BE-SRCH-082` Deployments MAY disable any modality other than `text` and choose devices per
  modality (CPU only, single GPU, GPU plus a separate indexing node).
- `BE-SRCH-083` Search MAY later be exposed on the integration API (e.g. for trusted suppliers'
  systems) as a versioned endpoint with its own scope ([BE-API-010, BE-API-012](204-api-surfaces.md)),
  reusing the same service, request options and both permission stages; the service account's
  roles decide `smart` access (BE-SRCH-091). Not offered now.

## Rationale

- One collection per modality and model makes models swappable: an upgrade is a reindex into a new
  collection, and the old one keeps serving until the switch.
- The page check always runs because a developer cannot know what users will attach to a generic
  field; a declaration that could only remove content would fail silently. The check is cheap (CPU,
  PDF structure); only the GPU embedding of visual pages is expensive, and it runs only on pages
  that need it.
- The audit stream as change feed means no app can forget to register a record for indexing.

## Compliance links

ISO 27001 A.5.15, A.8.3 (access restriction), A.8.11; GDPR Art. 17; ISO 15489 (disposition).
