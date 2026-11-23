# ADR template

Store ADRs in the affected repository under `docs/adr/NNNN-<slug>.md` (sequential numbers).

```markdown
# NNNN · <Title>

- Status: proposed | accepted | superseded by NNNN | withdrawn
- Date: YYYY-MM-DD
- Deciders: <roles or names>
- Guide version: x.y.z
- Rules concerned: <rule IDs, e.g. BE-FILE-007>

## Context
What problem or constraint makes this decision necessary.

## Decision
What is decided. For a deviation: which SHOULD rule is not followed and what is done instead.

## Consequences
Positive, negative, follow-up work, how conformance is still demonstrated.

## Review
When this ADR must be reviewed (date or trigger).
```

An ADR cannot override a MUST rule ([FND-GOV-005](../00-foundations/02-governance.md)).
