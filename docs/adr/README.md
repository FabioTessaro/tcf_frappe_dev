# Architecture Decision Records

Decisions about this repository (the development environment), and every
deviation from a SHOULD rule of the
[architecture guide](../../architecture/README.md), are recorded here
(rule `FND-GOV-004`).

- One file per decision: `NNNN-<slug>.md`, numbered in order, never renumbered.
- Use the [ADR template](../../architecture/90-appendices/adr-template.md).
- An ADR cannot override a MUST rule of the guide: change the guide instead.
- A decision that is replaced keeps its file, with status
  `superseded by NNNN`.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-dev-environment-follows-latest.md) | The development environment follows the latest images and tools | accepted |
| [0002](0002-github-as-interim-host.md) | GitHub is the interim git and CI host | accepted |
