#!/usr/bin/env bash
# Host backup script (guide 503 "Deploy host", 601). `just deploy` copies it
# from the released version to /srv/platform/<env>/ and runs it before changing
# anything.
#
# Contract: an encrypted, consistent backup of the database and the object
# store (OPS-BAK-001: the object-store snapshot is taken after the database
# backup), stored off-host and immutable for its retention (OPS-BAK-003);
# settings (destination, encryption key) come from the host's .env, never from
# this repository (DEL-CD-005). Print the backup ID on the last line of stdout;
# `restore.sh ID` must accept it.
#
# TODO: not implemented — there is no backup destination yet. Until it is, this
# script fails, so every deploy stops before changing the host (DEL-CD-003,
# DEL-CD-007). It is listed as open in docs/conformance.md.
set -euo pipefail

echo "backup.sh: not implemented yet (no backup destination): see deploy/host/backup.sh in the platform repository" >&2
exit 1
