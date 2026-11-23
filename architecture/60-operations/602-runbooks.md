# 602 · Runbooks

Runbooks are operational procedures kept in the `platform` repository under `docs/runbooks/`.
This chapter lists the ones that MUST exist.

## Required runbooks

| Runbook | Covers |
|---|---|
| `deploy.md` | The procedure in [50-delivery/503-cd](../50-delivery/503-cd.md) step by step |
| `rollback.md` | Previous image + restore |
| `restore.md` | Restore from backup to a given point in time |
| `incident.md` | Security incident handling and NIS2/GDPR reporting timeline |
| `audit-chain-mismatch.md` | Response to a failed audit-chain verification |
| `key-rotation.md` | Rotation of secrets, API keys, signing keys, age keys |
| `access-review.md` | Periodic review of users, roles, parties, service accounts |
| `antivirus-detection.md` | Handling of quarantined infected files |
| `onboarding-integration-client.md` | Creating a service account, scopes, sandbox access |

## Rules

- `OPS-RUN-001` Every runbook MUST be reviewed at least yearly and after every incident that used it.
- `OPS-RUN-002` Runbooks are controlled documents: versioned, reviewed by pull request.
