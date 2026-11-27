# 0008 · Releases promote the tested image; deploys can be rolled back

- Status: accepted
- Date: 2026-11-27
- Deciders: repository owner
- Guide version: 1.8.0
- Rules concerned: DEL-REL-004, DEL-REL-005 (new), DEL-CD-003, DEL-CD-004, DEL-CD-007 (new),
  OPS-BAK-001

## Context

Guide 1.7.0 said level 2 on `main` pushes the image "with the platform version tag". The platform
tooling pushed `main-<sha>` instead, and `just release` rebuilt the image and ran level 2 again:
the released image was a second build of the same lock, not the one tested on `main` and every
night since, and every release repeated the slowest part of the pipeline.

DEL-CD-004 defined a rollback (previous image plus restore of the pre-deploy backup) but nothing
implemented it: the deploy recorded neither the previous version nor which backup it took, and
the host had no restore contract.

## Decision

- **Release candidate:** level 2 on `main` pushes the tested image as `main-<sha>`, signed by
  digest, with the SBOM as a signed attestation.
- **Release = promotion:** `just release` finds the candidate of `main`'s HEAD, verifies its
  signature and attestation with `cosign.pub`, scans it again, and tags its digest with the
  version. Nothing is rebuilt; the release job needs no signing key.
- **Rollback:** `just rollback env` (workflow *CD · Platform · Rollback*), started by hand. It
  stops the platform, runs the host's `restore.sh` with the backup the last deploy took, and
  starts the previous version with its own compose file. Data written since that backup is lost;
  after a first deploy there is nothing to return to.
- **Deploy host contract:** `backup.sh` prints the backup ID; `restore.sh <ID>` restores it. Both
  live in the `platform` repository (`deploy/host/`), not on the host or in this repository: they
  are production tooling, reviewed and versioned with each release, and each deploy copies the
  released version's scripts to the host, so the restore always matches the backup. Settings
  (destination, encryption key) stay in the host's environment file. Until a backup destination
  exists, both are placeholders that fail, so no deploy gets past its backup. The deploy records `current-version` and `rollback.env`, refuses to start without both scripts, and
  refuses to start over a deploy that neither finished nor was rolled back.

Rejected: automatic rollback when the smoke test fails (a restore discards data, so a person
decides); rebuilding at release time (no added assurance once the candidate is re-scanned).

## Consequences

- No release without a green level 2 on the exact commit being released.
- `main-<sha>` images accumulate in the registry: a retention policy is needed once releases
  start.
- `deploy/host/backup.sh` and `restore.sh` must be implemented before the first deploy; the
  platform's `docs/conformance.md` lists them as open.
- Guide 1.8.0: 501 step 7, 502 (DEL-REL-005, release procedure), 503 (rollback procedure, deploy
  host, DEL-CD-007).

## Review

When the registry or the signing method changes, or after the first quarterly rollback test.
