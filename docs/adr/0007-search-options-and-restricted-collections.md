# 0007 · Search options, bounded results and restricted collections

- Status: accepted
- Date: 2026-11-27
- Deciders: repository owner
- Guide version: 1.7.0
- Rules concerned: BE-SRCH-006, 007, 038, 039, 051 (withdrawn), 083, 090–097, 100–103; BE-FILE-015;
  CT-SRCH-003, 006 (withdrawn), 007–011; SEC-OBS-007, 009–011; DOM-CLS model (`restricted_search`)

## Context

Guide 1.6.0 left open how export-controlled data is searched (open decision 10), how the
inference services are protected, and several request options the portal and Desk need before
the search component is built: an exact-only switch, older or cancelled records, thumbnails of
visual hits and bounded pagination.

## Decision

- **Export-controlled data:** restricted collections per modality, on hosts approved for that
  data, queried only for authorised users. Chosen now rather than excluding the data, because
  adding it later would mean reworking the index and the query path.
- **Inference services:** internal network and core's search backend only, authenticated, no
  content logging or disk cache, no outbound connections, `safetensors` weights pinned by
  checksum.
- **Who gets semantic search:** configured by role (default every System User; trusted external
  parties by role). Everyone else gets keyword search; record access is unchanged. Search on the
  integration API (for trusted suppliers' systems) stays a future option, not offered now.
- **Request options:** `mode` (`smart` or `exact`; exact means exact, no synonyms), `include` for
  cancelled and superseded records (indexed always, returned on request), optional `max_pages`
  per request (omitted: no limit); results
  carry `thumbnail` and `state`. Clients search on submit, not per keystroke. How any of this is
  displayed is left to the client.
- **Global search only:** filters by app, doctype and record state; no field or date filters.
  The reserved `filters` field is removed; field and date filtering stays in each doctype's list
  views (Frappe's own filtering).
- **Bounded refill:** pages emptied by permission checks are refilled within a per-request budget;
  a short page never says why.
- **Index unavailable or rebuilding:** keyword search answers.
- **Query logs:** metadata only by default; query text only by configuration, pseudonymised, at
  most 30 days.
- **DPIA:** required before semantic search is enabled in production, reviewed when a modality,
  model or query logging changes.
- **OCR:** one model per language of the language registry.

Rejected: excluding export-controlled data from semantic search (simpler, but a later switch
would touch the index layout and the query path); synonyms or typo tolerance in `exact` mode.

## Consequences

- A second Qdrant instance and inference services for the restricted zone, on approved hosts.
- Core's search settings gain the `smart` roles and the refill budget.
- Search exposes measurements and alerts (SEC-OBS-009…011) that also drive hardware reviews.

## Review

When semantic search is implemented, or when export-control obligations change.
