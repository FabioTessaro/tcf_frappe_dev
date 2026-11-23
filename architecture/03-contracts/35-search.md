# 35 · Search API contract

## Purpose

The request and response of the platform search, identical whether it is served by keyword search
(today) or by semantic search (later, [20-backend/210-search](../20-backend/210-search.md)).

## Endpoint

`<core-app>.search.api.search` (portal API, `portal_api`, rate tier `default`).

## Request

| Field | Type | Meaning |
|---|---|---|
| `q` | string, required | The user's query, any supported language |
| `apps` | list of app ids, optional | Only results from these apps |
| `doctypes` | list of doctype names, optional | Only results of these doctypes |
| `limit` | int, default 20, max 50 | Page size |
| `cursor` | string, optional | Opaque pagination cursor |

## Response

`items`: list of

| Field | Meaning |
|---|---|
| `app`, `doctype`, `name` | Identity of the record |
| `title` | Display title (from MariaDB) |
| `snippet` | Short excerpt with the matched passage (from MariaDB or extracted file text) |
| `route` | Where to open it: portal route from `record_routes`, or Desk form |
| `score` | Relevance, for ordering only (not comparable across queries) |
| `match_type` | `keyword`, `semantic` or `both` |
| `attachment` | Optional: file name when the match is inside an attachment |

plus `facets` (counts per app and per doctype for the current query, for filter chips), `cursor`
(next page) and `engine` (`keyword` or `semantic`).

## Filter options

`<core-app>.search.api.filter_options` returns the apps and doctypes the current user can read and
that are searchable, with translated labels.

## Rules

- `CT-SRCH-001` Filter options and facets MUST list only apps and doctypes the user can read; they
  MUST NOT reveal the existence of others.
- `CT-SRCH-002` The request and response schemas are pydantic models in core; the frontend types
  are generated ([31-generated-artifacts](31-generated-artifacts.md)).
- `CT-SRCH-003` Switching the engine from keyword to semantic MUST NOT change the contract;
  clients MAY display `engine` and `match_type` but MUST NOT depend on them.
- `CT-SRCH-004` The portal search component lives in core's shell; feature apps do not build their
  own global search. Feature-local list filtering inside a view is not "search" and is unaffected.
