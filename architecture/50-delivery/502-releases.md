# 502 · Versioning and releases

## Version schemes

| Thing | Scheme | Example |
|---|---|---|
| Platform release | Calendar: `YYYY.MM.PATCH` | `2026.12.0` |
| Apps | Semantic versioning, git tags `vX.Y.Z` | `v1.4.2` |
| Core sdk (frontend + backend, one number) | Semantic versioning, `core_sdk_version` | `1.4.0` |
| Integration API | Major version in URL | `/api/ext/v1/…` |
| This guide | Semantic versioning | `1.0.0` |

## Rules

- `DEL-REL-001` Commit messages MUST follow Conventional Commits (`feat:`, `fix:`, `docs:`,
  `refactor:`, `test:`, `chore:`, `ci:`; `!` or `BREAKING CHANGE:` for breaking changes) and SHOULD
  cite rule IDs when relevant.
- `DEL-REL-002` Changelogs are generated from commits with git-cliff; release notes of the platform
  aggregate app changelogs.
- `DEL-REL-003` Deprecations reference the platform release in which they started
  (`deprecated_since="2026.12"`) and are removed no earlier than the next platform release
  (portal API, sdk) or 12 months later (integration API).
- `DEL-REL-004` A platform release is a signed image plus its SBOM, `platform.lock`, release notes,
  and the guide version in force.
- `DEL-REL-005` A platform release MUST promote the release candidate of the released commit — the
  image level 2 built, tested and signed on `main` (`main-<sha>`, [501](501-ci.md) step 7) — to the
  version tag by digest, without rebuilding it. Before promoting, `just release` verifies the
  candidate's signature and SBOM attestation and scans it again; no candidate, no release.

## Release procedure (`just release version=…`)

1. Check the version scheme, a clean `main`, and that the tag does not exist yet.
2. Find the release candidate `main-<sha>` of `main`'s HEAD; verify its signature and SBOM
   attestation with the organisation's public key.
3. Scan it again (Trivy): vulnerabilities published since level 2 ran block the release.
4. Tag the candidate's digest with the version. The signature and the attestation belong to the
   digest, so they cover the version tag unchanged.
5. Generate the release notes (git-cliff) and push the git tag `YYYY.MM.PATCH`.
