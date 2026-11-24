# 0003 · Scaffolded repositories and the platform bootstrap

- Status: accepted
- Date: 2026-11-24
- Deciders: repository owner
- Guide version: 1.4.0
- Rules concerned: FND-CONF-001, FND-CONF-005, FND-CONF-006, DEL-TOOL-003, DEL-CI-002,
  DEL-CI-003

## Context

This repository will gain `new-platform.sh` (creates the `platform` repository once per
organisation) and `new-app.sh` (creates an empty core, foundation, feature or site app). Three
gaps in guide 1.3.0 blocked that:

- An empty scaffold cannot conform (the core app's portal is a blank page by design), yet
  FND-CONF-001 only allowed the README to say "Conforms to".
- DEL-TOOL-003 required shared tool configuration from `platform` without saying how.
- CI level 1 checks out required apps at their `platform.lock` version, but apps enter the lock
  only once they conform, so new apps had nothing to check out.

## Decision

Guide 1.4.0:

- a non-conforming repository declares `Targets Platform Architecture Guide x.y` and lists its
  open MUST rules in `docs/conformance.md` (FND-CONF-006);
- shared configuration is copied by `just sync-config` from a pinned `platform` commit (the
  same SHA the app's CI trigger file uses; platform tags exist only from the first release) and
  checked by `just check-config`; Renovate bumps the pin;
- required apps missing from `platform.lock` are checked out at `main` in level-1 CI;
- app trigger files call `platform`'s reusable app-CI workflow pinned to a commit SHA.

## Consequences

- Scaffolds start as `Targets 1.4` with a pre-filled list of open rules; they cannot be
  released until that list is empty (FND-CONF-005).
- A change to shared configuration or to the app CI is made once in `platform` and reaches apps
  through Renovate pull requests.
- Until apps conform, level-1 CI tests against moving `main` branches of their dependencies.

## Review

When the first apps enter `platform.lock`, check that the `main` fallback is no longer used.
