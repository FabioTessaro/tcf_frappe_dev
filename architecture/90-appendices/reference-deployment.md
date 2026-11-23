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

## CI/CD host (separate machine)

Forgejo (git, Actions, registry), forgejo-runner(s), Renovate, Weblate; optionally a log stack
(e.g. Grafana Loki) for centralised logs.

## Buckets

`attachments-vault`, `drive-vault`, `cad-vault` (existing in the dev bootstrap), plus
`public-assets`, `quarantine`, `audit-archive` (to add).

## Development environment

This repository's bootstrap (`setup.sh`, `initialize.sh`) provides the dev bench with a main site,
a test site (developer mode + allow_tests), MariaDB, Redis and SeaweedFS.
