# 307 · Rate limiting

## Tiers

| Tier | Keyed by | Typical use | Default limit (configurable in Core Settings) |
|---|---|---|---|
| `default` | User | Reads | 600 / min |
| `write` | User | Writes | 120 / min |
| `expensive` | User | Exports, reports, bulk actions (should usually become jobs) | 10 / min |
| `integration` | Integration client | Integration API | Per client, set on the client record |
| `guest` | IP | Guest API, password reset | 30 / min |
| `none` | — | Only with an ADR | — |

## Rules

- `SEC-RATE-001` Every sdk decorator MUST declare a tier (default `default` for reads, `write` for
  writes as declared).
- `SEC-RATE-002` Limits MUST be implemented with Frappe's rate limiter keyed as in the table and
  configured centrally, not hard-coded per endpoint.
- `SEC-RATE-003` Exceeding a limit returns `core.rate_limited` with `retry_after`.
- `SEC-RATE-004` Frappe's login rate limiting MUST be enabled; the forgot-password endpoint uses the
  `guest` tier.
- `SEC-RATE-005` The reverse proxy MUST apply coarse per-IP flood protection in front of the
  application limits.
