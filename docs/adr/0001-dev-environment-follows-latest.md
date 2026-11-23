# 0001 · The development environment follows the latest images and tools

- Status: accepted
- Date: 2026-11-23
- Deciders: repository owner
- Guide version: 1.2.0
- Rules concerned: SEC-VULN-005, SEC-VULN-010, SEC-VULN-006

## Context

The guide requires pinned dependencies for platform releases and app
repositories (`SEC-VULN-005`). This repository only provisions development
machines and containers; it produces no release artifacts. Pinning every image
(`frappe/bench`, SeaweedFS, Redis, ClamAV, Meet SFU) and every downloaded tool
(uv, gitleaks, lychee, hadolint, just, trivy, …) would require constant version
bumps for no release benefit, and would let the development environment drift
behind current versions.

## Decision

Following `SEC-VULN-010`, the development environment uses the `latest` tag of
its container images and installs the latest release of its tools. Exceptions:

- the MariaDB image follows a minor version (`11.8`) so the database volume
  stays compatible;
- pre-commit hooks keep a fixed `rev` (pre-commit requires one) and are
  updated with `pre-commit autoupdate`.

## Consequences

- Developers always work against current versions; an upstream change can
  break `./initialize.sh` until this repository adapts.
- Two developers setting up on different days may get different tool versions.
  When reproducibility matters (for example while investigating a bug), compare
  the versions printed by `./initialize.sh` (container tools step) and in its log.
- Nothing from this repository reaches a platform release, which stays pinned
  under `SEC-VULN-005`.
- Secret scanning (`SEC-VULN-006`) still applies: gitleaks runs as a git hook.

## Review

When the `platform` repository and its pinned `platform.lock` exist, decide
whether the development environment should read its versions from it
(`DEL-REPO-003`).
