# 500 · Repositories

## Layout

| Repository | Holds |
|---|---|
| `<core-app>` | Core app (backend, frontend toolchain, sdks) |
| One per feature app, foundation app and site app | That app |
| **`platform`** | `platform.lock`, production `Dockerfile`, production and e2e compose files, CI pipeline scripts and reusable workflow definitions, the CI image definition, platform contract checks, release notes, **this architecture guide** once moved there (see open decisions) |
| Development environment (this repository) | Dev bootstrap scripts; reads the same app list and versions |

## `platform.lock`

A TOML file listing Frappe and every app with repository URL and exact version (tag, plus commit
SHA). It is the single definition of a platform release.

## Rules

- `DEL-REPO-001` Every app lives in its own repository; monorepos are not used.
- `DEL-REPO-002` A combination of app versions is releasable only if it is recorded in
  `platform.lock` and passed level-2 CI.
- `DEL-REPO-003` The development bootstrap SHOULD read app versions from `platform.lock` so dev,
  CI and production run the same versions.
- `DEL-REPO-004` Every repository MUST contain: `README.md` (with conformance statement),
  `SECURITY.md`, `justfile`, `.pre-commit-config.yaml`, CI trigger file, `docs/adr/`, lockfiles,
  `renovate.json`.
- `DEL-REPO-005` The default branch is `main`, protected: changes only via pull request with green
  CI and at least one review. Force-pushes to `main` are forbidden. On GitHub this is enforced
  with branch rulesets.
- `DEL-REPO-006` Repositories are hosted in the organisation's GitHub account (interim host, see
  [open decision 7](../90-appendices/open-decisions.md)); mirrors to other hosts MAY exist but are
  never the source of truth.
