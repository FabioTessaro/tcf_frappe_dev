# 0002 · GitHub is the interim git and CI host

- Status: accepted
- Date: 2026-11-24
- Deciders: repository owner
- Guide version: 1.3.0
- Rules concerned: DEL-REPO-005, DEL-REPO-006, DEL-CI-002, DEL-CI-004, DEL-CI-006, DEL-CI-007,
  DEL-TOOL-001, DEL-TOOL-002

## Context

Guide 1.2.0 chose a self-hosted Forgejo instance for git hosting, CI (Forgejo Actions and
forgejo-runner), the container registry and Renovate. The organisation cannot run and secure
that infrastructure yet. No repository had moved to Forgejo; this repository already lives on
GitHub.

## Decision

Change the guide (1.3.0) so that GitHub is the interim host:

- git hosting on GitHub, with `main` protected by branch rulesets;
- GitHub Actions on GitHub-hosted runners as the CI trigger, running `just` recipes inside the
  pinned CI image (`container:`);
- GitHub Container Registry (`ghcr.io`) for the signed platform image;
- Renovate run as a scheduled GitHub Actions job, not as a server or hosted app;
- deploy approval through GitHub environments with required reviewers.

To keep a later move to self-hosting cheap, the guide forbids GitHub-only pipeline features
(CodeQL / Advanced Security, Marketplace actions doing pipeline work, Dependabot) and limits
actions to plumbing, with third-party actions pinned to a commit SHA (`DEL-CI-007`).

## Consequences

- No CI host to run or patch; runners are separate from production by construction.
- Source code, CI logs and the image registry are on a third-party service. Secrets still come
  from SOPS files or scoped GitHub secrets and never appear in logs (`DEL-CI-006`).
- Some protections depend on the GitHub plan, especially for private repositories: branch
  rulesets, environment secrets and required reviewers on environments. Check the plan before
  relying on them for `DEL-REPO-005` and the deploy approval in 503.
- Weblate and a central log stack still need a host; that question stays in open decision 7.

## Review

When self-hosting becomes possible, revisit open decision 7 (Forgejo is the candidate).
