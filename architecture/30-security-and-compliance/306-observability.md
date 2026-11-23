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
  object store and antivirus, and MUST be used by the deploy smoke test.
- `SEC-OBS-008` Employee activity logs are subject to [SEC-AUD-010](302-audit.md).
