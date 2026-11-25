# 0005 · platform.lock follows release tags

- Status: accepted
- Date: 2026-11-25
- Deciders: repository owner
- Guide version: 1.5.1
- Rules concerned: DEL-REPO-002, DEL-REL-001, DEL-CI-001

## Context

Guide 1.5.0 said, in 501 level 2 step 1, that merging to `main` in an app
repository triggers Renovate. The tooling works differently: the shared
Renovate preset (`platform/default.json`) reads `platform.lock` with the
`git-tags` datasource, so it proposes new tags, not new commits on `main`, and
it runs on a schedule (`platform/.github/workflows/renovate.yml`).

The cross-repository section said the `platform` pull request's lock "points
at the PR branches". Level 2 starts with `just check-lock-remote`, which
requires every `version` to be a tag pointing to the locked commit, and the
image build clones apps at their tags, so a lock pointing at branches fails.

## Decision

Guide 1.5.1 describes what the tooling does:

- An app reaches `platform.lock` only through a release tag `vX.Y.Z`; Renovate
  opens the bump on its next scheduled run. Untagged merges never do.
- Cross-repository changes are tested in `platform` with pre-release tags
  `vX.Y.Z-rc.N` on the PR branches, set by hand. Renovate ignores pre-release
  tags. After the app pull requests merge, release tags replace them before
  the `platform` pull request merges.

Rejected: teaching `tools/lock.py` to accept branches (a lock that can name a
moving reference weakens DEL-REPO-002 for a rare case).

## Consequences

- Releasing an app is an explicit act (pushing a tag), separate from merging.
- A bump reaches `platform` up to one Renovate interval after the tag; run the
  `renovate` workflow by hand to go faster.
- Cross-repository changes need a few manual tags and lock edits.

## Review

When Renovate is replaced, or cross-repository changes become frequent.
