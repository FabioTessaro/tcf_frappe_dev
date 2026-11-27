#!/usr/bin/env bash
# Host restore script (guide 503 "Deploy host", 601). `just rollback` runs the
# copy that the last deploy put in /srv/platform/<env>/, with the backup ID that
# deploy recorded, while every platform container is stopped.
#
# Contract: restore.sh ID restores that backup, database and object store
# together (OPS-BAK-001), into the running db and objects services of this
# environment; it exits non-zero if anything fails.
#
# TODO: not implemented — there is no backup destination yet (see backup.sh).
# A deploy cannot get past its backup until both scripts are implemented, so
# there is nothing to restore yet.
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: restore.sh BACKUP_ID" >&2; exit 2; }
echo "restore.sh: not implemented yet (no backup destination): cannot restore $1" >&2
exit 1
