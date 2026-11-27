# Reference deployment (non-normative)

Describes the deployment the guide was written against. Normative requirements are in the
chapters; this appendix shows one way to satisfy them.

## Production host (VPS, Docker Compose)

| Service | Image / tool | Notes |
|---|---|---|
| Reverse proxy | Caddy or nginx | TLS, security headers, per-IP flood protection, `files.<domain>` route to the object store S3 endpoint for presigned transfers |
| Frappe web | Platform image | gunicorn |
| Workers (short, default, long) | Platform image | RQ workers |
| Scheduler | Platform image | |
| socket.io | Platform image | |
| MariaDB | Pinned version | Encrypted volume, binary logs on |
| Redis (cache, queue) | Pinned version | |
| SeaweedFS | Pinned version (never `latest`) | S3 API; buckets per storage class |
| ClamAV | Pinned version | `virus_scanner` capability provider |
| Qdrant (planned) | Pinned version | Semantic search index; internal network only |
| Search inference, `text` (planned) | Pinned version | BGE-M3 embeddings and the reranker; CPU possible, GPU for bulk indexing |
| Search inference, `visual` (planned) | Pinned version | Page-image embeddings; GPU; may be disabled ([BE-SRCH-082](../20-backend/210-search.md)) |
| Restricted search zone (planned) | Pinned versions | Qdrant and inference services for export-controlled content, on a host approved for that data ([BE-SRCH-101](../20-backend/210-search.md)) |
| Apache Tika (planned) | Pinned version | Type detection and text extraction for the derivation pipeline |
| Search workers (planned) | Platform image | RQ workers on the per-modality queues, live lane before backfill lane |

## Search hardware profiles (planned)

Sizing is deployment configuration ([BE-SRCH-082](../20-backend/210-search.md)); reference sizing
per profile is open decision 15. The chosen profile is reviewed against the search measurements
([SEC-OBS-009…011](../30-security-and-compliance/306-observability.md)).

| Profile | `text` | `visual` |
|---|---|---|
| CPU only | CPU | Disabled; media pages indexed from OCR text ([BE-SRCH-063](../20-backend/210-search.md)) |
| Single GPU | GPU (shared) | GPU (shared) |
| GPU + indexing node | Query encoding on the main host, bulk indexing on the node | Same |

## CI/CD (GitHub, interim)

GitHub (git, Actions on GitHub-hosted runners, Container Registry); Renovate runs as a scheduled
Actions job. Weblate and an optional log stack (e.g. Grafana Loki) need a separate host once
self-hosting is possible ([open decision 7](open-decisions.md)); that host would then also be the
candidate for Forgejo.

## Buckets

`attachments-vault`, `drive-vault`, `cad-vault`, `public-assets`, `quarantine`, `audit-archive`
(one per storage class of [208-files](../20-backend/208-files.md); all suggested by the dev bootstrap).

## Development environment

This repository's bootstrap (`setup.sh`, `initialize.sh`) provides the dev bench with a main site,
a test site (developer mode + allow_tests), MariaDB, Redis and SeaweedFS.
