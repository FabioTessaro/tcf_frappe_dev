# 600 · Environments

| Environment | Site(s) | Data | Purpose |
|---|---|---|---|
| Development | `<site>` (dev), `test.<site>` (developer mode + allow_tests) | Synthetic (seeds) | Daily development; Playwright and `bench run-tests` locally |
| CI | Disposable stacks: minimal and full test sites | Synthetic | Level-1 and level-2 pipelines |
| Staging | One site | Synthetic | Release verification; integration sandbox for external clients |
| Production | One site | Real | Operation |

## Rules

- `OPS-ENV-001` One Frappe site per environment (no multi-tenancy).
- `OPS-ENV-002` Real personal or customer data MUST exist only in production (and its backups).
- `OPS-ENV-003` Production configuration differs from staging only in `site_config.json`, secrets
  and sizing; the image is identical.
- `OPS-ENV-004` `developer_mode` and `allow_tests` MUST be off in staging and production.
