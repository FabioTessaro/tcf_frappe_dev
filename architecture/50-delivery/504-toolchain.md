# 504 · Toolchain (decided)

## Status

**Every tool in this chapter is decided.** It is a MUST to use these tools for the stated purpose.
Substituting, adding a parallel tool for the same purpose, or removing one requires a change to this
guide (not just an ADR). This applies to humans and AI agents alike.

Exact tool versions are pinned in each repository (lockfiles, `.pre-commit-config.yaml`, the CI
image in `platform`) and updated only through Renovate pull requests.

## Selection criteria

Open source, self-hostable, no dependency on a specific git hosting platform, runnable locally
exactly as in CI.

**Interim exception:** git hosting, CI triggers, the container registry and CI secrets use
**GitHub** until the platform can self-host
([open decision 7](../90-appendices/open-decisions.md)). Pipeline logic stays in `just` recipes
running in the CI image, and no GitHub-only pipeline feature is used, so a later move to a
self-hosted host replaces only trigger files, secrets and registry paths.

## Runtime baseline

| Purpose | Tool |
|---|---|
| Framework | Frappe 16 |
| Python | 3.14 (as required by Frappe 16) |
| Node.js | ≥ 24 (as required by Frappe 16) |
| Containers | Docker Engine with BuildKit (buildx), Docker Compose |

## Python

| Purpose | Tool | Notes |
|---|---|---|
| Package and environment management | **uv** | `uv.lock` committed |
| Lint (incl. security `S` rules) and format | **Ruff** | Replaces black, isort, flake8, bandit |
| Type checking | **mypy** with the pydantic plugin | `strict = true` for new code; `sdk`, `service.py`, `schemas.py` must pass strict |
| Import boundaries | **import-linter** | Contracts per app (BE-STR-004/005, SYS-DEP-004) |
| Schemas | **pydantic** — the version pinned by Frappe | Apps never pin pydantic |
| Tests | **Frappe test runner** (`bench run-tests`) | Unittest-based, as Frappe |
| Coverage | **coverage.py** | |

## Frontend

| Purpose | Tool | Notes |
|---|---|---|
| Package manager | **yarn** (as used by Frappe) | `yarn.lock` committed; only in `<core-app>/frontend` |
| Build | **Vite** | With the three custom plugins |
| Type checking | **vue-tsc** | `strict: true` |
| Lint | **ESLint** (flat config) with `typescript-eslint`, `eslint-plugin-vue`, `eslint-plugin-boundaries`, `eslint-plugin-security` | |
| Format | **Prettier** | ESLint does not format |
| Style lint | **Stylelint** (`stylelint-config-standard-scss` + custom token rules) | |
| Unit / integration / contract tests | **Vitest** + **Vue Test Utils** | |
| Network mocking | **MSW** | |
| Coverage | **@vitest/coverage-v8** | |
| E2E | **Playwright** | |
| Accessibility | **axe-core** (`vitest-axe`, `@axe-core/playwright`) | |
| Component stories (optional) | **Storybook** | Only for shared components |

## Repository hygiene

| Purpose | Tool |
|---|---|
| Git hooks | **pre-commit** (framework already used in the dev environment) |
| Commit message convention | **Conventional Commits**, checked by the `conventional-pre-commit` hook and in CI |
| Changelog generation | **git-cliff** |
| Secret scanning | **gitleaks** (pre-commit and CI) |
| Shell scripts | **shellcheck** |
| Dockerfiles | **hadolint** |
| Markdown (incl. this guide) | **markdownlint-cli2** and **lychee** (link checker) |
| Task runner | **just** (`justfile` in every repository) |

## CI/CD and supply chain

| Purpose | Tool |
|---|---|
| Git hosting | **GitHub** (organisation account; interim, see open decision 7) |
| CI trigger and runners | **GitHub Actions** on GitHub-hosted runners (separate from production by construction) |
| Container and package registry | **GitHub Container Registry** (`ghcr.io`) |
| Dependency updates | **Renovate**, run as a scheduled GitHub Actions job (no Renovate server, no hosted Renovate app) |
| Vulnerability and licence scanning | **Trivy** |
| SBOM | **Syft** (CycloneDX JSON) |
| Image signing | **cosign** with organisation-held keys (no public transparency log required) |
| Secrets in repositories | **SOPS** with **age** keys |

## Documentation and translation

| Purpose | Tool |
|---|---|
| Guide and docs site | **MkDocs** with the Material theme |
| Translation management | **Weblate** (self-hosted), for portal JSON and `.po` files |

## Runtime services referenced by the guide (reference deployment)

| Purpose | Tool |
|---|---|
| Object storage | **SeaweedFS** (S3 API), pinned version |
| Antivirus | **ClamAV** (provides the `virus_scanner` capability) |
| Reverse proxy and TLS | **Caddy** or **nginx** (deployment choice; must satisfy SEC-BASE-004/007, SEC-RATE-005) |
| Semantic search index (planned, [210-search](../20-backend/210-search.md)) | **Qdrant**, pinned version |
| Embedding service (planned) | **Hugging Face Text Embeddings Inference** (self-hosted); model pending (candidate BGE-M3) |

## Explicitly not used

Do not introduce these (or other tools for the same purposes) without changing this guide.

| Tool | Reason |
|---|---|
| GitLab CI, Jenkins, other CI systems | One trigger system only; GitHub Actions only triggers portable recipes |
| Dagger, Make (as main runner) | `just` chosen for simplicity |
| Woodpecker CI, self-hosted Forgejo (for now) | No self-hosting yet; Forgejo is the candidate target of open decision 7, and recipes keep the switch cheap |
| Harbor | GitHub Container Registry sufficient; revisit if image policies are needed |
| Dependabot | Renovate chosen: one update tool, and it also runs on a self-hosted host |
| GitHub-only pipeline features (CodeQL / GitHub Advanced Security, Marketplace actions that lint, test, build, scan or release) | Puts pipeline logic outside `just` and ties it to GitHub; Ruff `S`, eslint-plugin-security, gitleaks and Trivy cover the baseline |
| black, isort, flake8, pylint, bandit (standalone) | Covered by Ruff |
| pyright | mypy chosen (pydantic plugin) |
| poetry, pip-tools, pipenv | uv chosen |
| npm, pnpm | yarn (aligned with Frappe) |
| Jest, Cypress, Selenium | Vitest and Playwright chosen |
| Husky, lefthook | pre-commit chosen |
| Semgrep | Not adopted now; Ruff `S` rules and eslint-plugin-security cover the baseline |
| SaaS scanners or monitoring (Snyk, Sentry SaaS, Crowdin, ...) | Self-hosted only |
| MariaDB native `VECTOR` columns, sqlite-vec | Qdrant chosen as the only vector index |
| Frappe Flow knowledge store (`frappe.flow.knowledge`) | No per-user permission checks; Qdrant chosen for search |
| External embedding or AI APIs for record content (OpenAI, Cohere, ...) | Record content stays on self-hosted infrastructure |

## Rules

- `DEL-TOOL-001` The tools above MUST be used for their stated purposes.
- `DEL-TOOL-002` Tools in *Explicitly not used* MUST NOT be introduced without changing this guide.
- `DEL-TOOL-003` Tool configuration shared by all repositories (Ruff, mypy, ESLint, Prettier,
  Stylelint, markdownlint, pre-commit hooks) MUST come from the `platform` repository's shared
  configuration; repositories MAY only add stricter settings. Each repository copies it with
  `just sync-config` from a pinned `platform` commit (the SHA its CI trigger file uses),
  `just check-config` fails on any drift from that commit, and Renovate bumps the pin.
- `DEL-TOOL-004` Every tool MUST be runnable locally through `just` with the same result as in CI.
- `DEL-TOOL-005` Frappe Flow (`frappe.flow`, Frappe's AI-agent framework) MUST NOT be used for
  search and SHOULD NOT be used anywhere else on the platform; any other use requires an ADR that
  addresses per-user permissions, classification and where data is sent.
