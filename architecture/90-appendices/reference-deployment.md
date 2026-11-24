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
| Text Embeddings Inference (planned) | Pinned version | Self-hosted embedding service; GPU optional for bulk indexing |

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
