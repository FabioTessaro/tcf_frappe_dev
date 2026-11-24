# 0004 · Single-maintainer repositories merge after self-review

- Status: accepted
- Date: 2026-11-24
- Deciders: repository owner
- Guide version: 1.5.0
- Rules concerned: DEL-REPO-005, FND-CONF-003, BE-API-021

## Context

Guide 1.4.0 required at least one approving review on every pull request.
GitHub does not let authors approve their own pull requests, so a repository
with one developer could never merge anything. The platform starts with a
single developer.

## Decision

Guide 1.5.0: the pull request and green CI stay mandatory for everyone. An
approval by someone other than the author is required only when a repository
has two or more maintainers. A single maintainer merges after completing the
self-review checklist of `.github/pull_request_template.md` (shared
configuration), which lists the manual-review rules (FND-CONF-003), including
the security review of guest endpoints (BE-API-021).

`new-platform.sh` and `new-app.sh` ask "solo or team" and set the ruleset's
required approvals to 0 or 1; running them again with the other answer
switches.

Rejected: letting admins bypass the review rule (records a review requirement
that is silently skipped) and direct pushes to `main` (loses the CI gate).

## Consequences

- Every change still has a pull request, CI results and a checklist on record;
  the record says "self-reviewed" truthfully.
- Self-review is weaker evidence than independent review. When a second
  maintainer joins, switch the repositories to "team".

## Review

When a second developer joins.
