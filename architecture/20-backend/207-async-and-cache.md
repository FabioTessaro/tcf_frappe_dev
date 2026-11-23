# 207 · Jobs, scheduler, realtime and cache

## Rules

- `BE-ASYNC-001` Background work MUST be enqueued through `sdk.jobs.enqueue`, which propagates
  `trace_id`, the acting user and audit context.
- `BE-ASYNC-002` Jobs and scheduled tasks live in the slice's `jobs.py` and are registered in
  `hooks.py` (`scheduler_events`). They call services.
- `BE-ASYNC-003` Any operation expected to exceed 5 seconds, or processing more than a page of
  records, MUST run as a job; the API returns a job reference and progress is reported over
  realtime.
- `BE-ASYNC-004` Jobs MUST be idempotent or guarded against double execution.
- `BE-ASYNC-005` Realtime publishing follows [03-contracts/34-realtime-events](../03-contracts/34-realtime-events.md).
- `BE-ASYNC-006` Cache keys MUST be namespaced `<app>:<feature>:…`; invalidation lives in the
  slice's `events.py`. Cached values MUST NOT bypass permission checks (cache per user or cache
  only permission-independent data).
