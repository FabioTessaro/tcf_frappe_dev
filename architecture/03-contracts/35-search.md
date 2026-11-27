# 35 · Search API contract

## Purpose

The request and response of the platform search, identical whether it is served by keyword search
(today) or by semantic search (later, [20-backend/210-search](../20-backend/210-search.md)), and
whether it is called from the portal or from Desk.

## Endpoint

`<core-app>.search.api.search` (portal API, `portal_api`, rate tier `default`).

## Request

| Field | Type | Meaning |
|---|---|---|
| `q` | string, required | The user's query, any supported language |
| `apps` | list of app ids, optional | Only results from these apps |
| `doctypes` | list of doctype names, optional | Only results of these doctypes |
| `mode` | string, default `smart` | Open set: `smart` (semantic and keyword) or `exact` (keyword only, exact terms); see BE-SRCH-090, 091 |
| `include` | list of record states, optional | Also return records in these states (open set: `cancelled`, `superseded`); by default only active records are returned |
| `limit` | int, default 20, max 50 | Maximum results per page |
| `max_pages` | int, optional | Maximum pages reachable through `cursor`, set per request; omitted means no limit (all results) |
| `cursor` | string, optional | Opaque pagination cursor |

## Response

`items`: list of

| Field | Meaning |
|---|---|
| `app`, `doctype`, `name` | Identity of the record |
| `title` | Display title (from MariaDB) |
| `snippet` | Optional: short excerpt with the matched passage (from MariaDB or derived file text); absent when the match has no text (e.g. a drawing page without usable OCR) |
| `highlights` | Optional: list of `[start, end]` character ranges within `snippet` that matched the query; clients MAY ignore them |
| `route` | Where to open it: portal route from `record_routes`, or Desk form |
| `score` | Relevance, for ordering only (not comparable across queries) |
| `match_type` | Open set: `keyword`, `semantic` (text meaning), `visual` (page image), `both` (more than one of these) |
| `attachment` | Optional: file name when the match is inside an attachment |
| `page` | Optional: 1-based page of `attachment` where the match is, so the client can open the file at that page |
| `thumbnail` | Optional: link to a thumbnail of that page, through the file download route (permission-checked, audited) |
| `state` | Record state (`active` unless requested through `include`) |
| `more_matches` | Optional: number of further matches in the same record (other pages, chunks or attachments) not listed separately |

plus `facets` (counts per app and per doctype, with translated labels, for filter chips; see
CT-SRCH-009), `cursor` (next page) and `engine` (open set: `keyword` or `semantic`). There is
deliberately no total result count.

## Filter options

`<core-app>.search.api.filter_options` returns the apps and doctypes the current user can read and
that are searchable, with translated labels.

## Rules

- `CT-SRCH-001` Filter options and facets MUST list only apps and doctypes the user can read; they
  MUST NOT reveal the existence of others.
- `CT-SRCH-002` The request and response schemas are pydantic models in core; the frontend types
  are generated ([31-generated-artifacts](31-generated-artifacts.md)).
- `CT-SRCH-003` Switching the engine from keyword to semantic MUST NOT change the contract;
  clients MAY display `engine` and `match_type` but MUST NOT depend on them. How results are shown
  (thumbnails, snippets, the `mode` switch, the `include` toggle, their labels) is the client's
  choice; this contract fixes only the data.
- `CT-SRCH-004` The portal search component lives in core's shell; feature apps do not build their
  own global search. Feature-local list filtering inside a view is not "search" and is unaffected.
- `CT-SRCH-005` Enumerated response values (`match_type`, `engine`) are **open sets**: new values
  MAY be added in a minor version, and clients MUST handle unknown values (display them generically
  or ignore them) instead of failing.
- `CT-SRCH-006` *Withdrawn in 1.7.0: the reserved `filters` field is removed (CT-SRCH-011).*
- `CT-SRCH-007` Clients MUST call search on an explicit submit (e.g. Enter or a button), not on
  every keystroke.
- `CT-SRCH-008` A page MAY contain fewer items than `limit`, also when more pages follow
  ([BE-SRCH-039](../20-backend/210-search.md)); `cursor` is empty when no further page exists or
  the request's `max_pages` is reached. Each page is one request with its own refill budget, so a
  search without `max_pages` never makes the user wait longer than one page.
- `CT-SRCH-009` Facet counts are **approximate**: they count the results that passed both
  permission stages so far for this query, not every match in the index. Clients MUST NOT present
  them as exact totals. A total result count MUST NOT be added, because computing it would require
  permission-checking every candidate in the index.
- `CT-SRCH-010` Several matches inside one record (pages, chunks, attachments) are returned as one
  item carrying the best match; `more_matches` MAY report how many others there are.
- `CT-SRCH-011` The global search filters only by app, doctype (BE-SRCH-030) and record state
  (`include`); it has no field or date filters. Searching by field values or dates belongs to each
  doctype's own list views (Desk list filters, portal feature lists), which are unaffected
  (CT-SRCH-004).
