# 03 · Conformance

## Purpose

What it means for a repository to conform to this guide, and how it is shown.

## Rules

- `FND-CONF-001` Every app repository MUST declare the guide version in its `README.md`: either
  `Conforms to Platform Architecture Guide x.y` when FND-CONF-002 holds, or
  `Targets Platform Architecture Guide x.y` while it does not yet conform (for example a freshly
  scaffolded app).
- `FND-CONF-006` A repository that declares `Targets` MUST list the applicable MUST rules that do
  not hold yet in `docs/conformance.md` (section *Open rules*). It switches to `Conforms to` when
  that list is empty and CI passes; until then FND-CONF-005 keeps it out of `platform.lock`.
- `FND-CONF-002` A repository conforms when all MUST rules applicable to it hold, every SHOULD
  deviation has an ADR, and all automated checks listed under *Verification* pass in CI.
- `FND-CONF-003` Rules that cannot be checked automatically are marked *manual review*. They
  MUST be part of the pull-request review checklist of the repository
  (`.github/pull_request_template.md`, from the shared configuration), used by the reviewer or,
  in a single-maintainer repository, by the author as self-review (DEL-REPO-005).
- `FND-CONF-004` Upgrading to a new **major** guide version MUST be tracked as work in each
  repository; until finished, the repository keeps declaring the previous version.
- `FND-CONF-005` An app that is non-conforming MUST NOT be added to `platform.lock`
  (see [50-delivery/500-repositories](../50-delivery/500-repositories.md)).

## Defaults

- `FND-CONF-010` Each repository SHOULD keep a `docs/conformance.md` listing the rule IDs it
  implements in a non-trivial way and where (file or test), to support audits.

## Verification

- Automated: the CI levels in [50-delivery/501-ci](../50-delivery/501-ci.md).
- Manual: pull-request checklist generated from the *manual review* rules.

## Compliance links

ISO 9001/EN 9100 §7.5 (documented information), §8.3 (design and development control);
ISO 27001 A.8.25–A.8.28 (secure development).
