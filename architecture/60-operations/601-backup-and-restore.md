# 601 · Backup and restore

## Rules

- `OPS-BAK-001` Database and object store MUST be backed up **consistently**: a database backup is
  only valid together with an object-store snapshot taken after it (files referenced by the DB
  exist in the snapshot).
- `OPS-BAK-002` Schedule: database daily full plus binary logs (point-in-time recovery ≤ 15 min);
  object store daily incremental snapshot; before every deploy (DEL-CD-003).
- `OPS-BAK-003` Backups MUST be encrypted, stored off-host (at least one copy at a different
  location) and immutable for their retention period.
- `OPS-BAK-004` The `audit-archive` storage class is backed up with at least the audit retention.
- `OPS-BAK-005` A **restore test** to a scratch environment MUST run at least quarterly and its
  result MUST be recorded (date, backup used, duration, verification of the audit chain).
- `OPS-BAK-006` Recovery objectives (defaults, to confirm by the business impact analysis):
  RPO ≤ 15 minutes, RTO ≤ 8 hours.

## Compliance links

ISO 27001 A.8.13, A.5.29–A.5.30; NIS2 Art. 21(2)(c); ISO 22301 (optional target).
