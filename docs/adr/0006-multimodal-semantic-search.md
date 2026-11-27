# 0006 · Multimodal semantic search with swappable models

- Status: accepted
- Date: 2026-11-27
- Deciders: repository owner
- Guide version: 1.6.0
- Rules concerned: BE-SRCH-002, 005, 018, 019, 024, 025, 035, 037, 038, 041, 043, 060–063,
  070–073; BE-FILE-012–014; CT-SRCH-005, 006; DEL-TOOL-006

## Context

Guide 1.1.0 planned semantic search with one text-only embedding service (Text Embeddings
Inference, candidate BGE-M3) and plain text extraction from files. Much of the company's content
carries its meaning in drawings, scans and page layout, which text embeddings miss. Models improve
quickly, so whatever is chosen now must be replaceable, even at the cost of a full reindex.

## Decision

- Search is organised by **modality**: `text` (record fields and text pages, BGE-M3, dense and
  sparse) and `visual` (page images, a late-interaction model; candidate ColQwen family). The
  design handles N modalities; `image` (photos) is reserved.
- Models are described only in a **modality registry**. Each modality has its own inference
  service and its own Qdrant collection behind an alias; a model upgrade fills a new collection and
  switches the alias.
- A CPU **page check** always runs on every page of a searchable attachment and routes it to one or
  more modalities using configured rules ("in doubt, both"). The search declaration can only
  **add** modalities (`routing`), never remove them, so a wrong declaration cannot drop content.
- Files go through a **derivation pipeline** (Apache Tika, then layout and OCR) whose derived
  objects inherit classification, retention and erasure; page images are rendered on demand.
- Queries fuse every modality's results and an exact-identifier lookup, check permissions in
  MariaDB, then rerank on text. A missing service degrades the query instead of failing it.
- Desk record search MUST use the same API once semantic search is enabled; until then Desk keeps
  Frappe's standard search and the portal uses keyword search.
- Models must be open source with published weights and self-hosted, preferably free for
  commercial use; a paid licence only by ADR when no free alternative is adequate.
- The search API reserves `filters` and adds `page`; enumerated values are open sets.

Rejected:

- A declaration-only text/media split: a developer cannot know what users attach to a generic
  field, and a `text` declaration would silently lose diagrams.
- A registration queue filled by apps: the audit stream already gives an ordered, durable feed with
  no app code.
- One unified text-and-visual model: the candidates found carry non-commercial licences.

## Consequences

- Apps only add optional routing hints to their search declarations; no other app change.
- Core must build the registry, the page check, per-modality queues and collections, and the
  derivation pipeline.
- A GPU is needed for the `visual` modality; CPU-only deployments disable it and index media pages
  from OCR text.
- Open decisions 9 and 11–16 track the choices still pending.

## Review

When open decisions 11–16 are closed, or when semantic search is implemented.
