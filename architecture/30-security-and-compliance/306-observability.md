# 306 · Observability

## Rules

- `SEC-OBS-001` Correlation: `X-Trace-Id` per user action ([SYS-LIFE-001](../01-system/13-request-lifecycle.md)),
  stored in `frappe.local`, included in every log line, error envelope, job, realtime payload and
  Audit Event.
- `SEC-OBS-002` Logging MUST use `sdk.logging.get_logger("<app>.<feature>")`, emitting structured
  JSON with at least: timestamp, level, logger, trace_id, user, app, feature, event, error code.
- `SEC-OBS-003` `frappe.monitor` MUST be enabled in staging and production for request and job
  timing.
- `SEC-OBS-004` Unexpected errors (`core.internal`) MUST be recorded in Frappe's Error Log with the
  trace_id, and the trace_id shown to the user so support can find them.
- `SEC-OBS-005` Logs MUST NOT contain secrets or personal data beyond identifiers ([SEC-PRIV-003](305-privacy.md)).
- `SEC-OBS-006` Logs are retained per the `operational_logs` retention class (default 12 months)
  and shipped to a central, self-hosted store when one exists (reference stack in
  [90-appendices/reference-deployment](../90-appendices/reference-deployment.md)).
- `SEC-OBS-007` Health checks MUST exist for web, workers, scheduler, socket.io, database, Redis,
  object store and antivirus (and, where semantic search is enabled, Qdrant and every enabled
  inference service, restricted zone included), and MUST be used by the deploy smoke test.
- `SEC-OBS-008` Employee activity logs are subject to [SEC-AUD-010](302-audit.md).
- `SEC-OBS-009` **Search measurements.** Semantic search ([20-backend/210-search](../20-backend/210-search.md))
  MUST expose, per modality and per zone (normal, restricted) where relevant: indexing lag (age of
  the oldest unprocessed audit event), queue depth per lane (live, backfill), failed indexing and
  extraction jobs, query latency and error rate per inference service, share of queries answered by
  a fallback, drift found by the nightly reconciliation, and index storage used.
- `SEC-OBS-010` Alerts MUST exist at least on indexing lag, a backlog that does not shrink over a
  night, the fallback share, failed jobs and index storage. Thresholds are deployment
  configuration, because they depend on the hardware.
- `SEC-OBS-011` The search hardware profile
  ([90-appendices/reference-deployment](../90-appendices/reference-deployment.md)) SHOULD be
  reviewed against SEC-OBS-009 measurements at least yearly and whenever an alert of SEC-OBS-010
  recurs; the review is the evidence for upgrading or not upgrading hardware.
