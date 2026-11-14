#!/usr/bin/env bash
# Set up the development pipeline inside the Frappe Dev Container.
# This script never creates or modifies the project .env file.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ ! -f "$ROOT_DIR/.env" ]]; then
  echo "Project .env file not found." >&2
  echo "Run ./install.sh on the host to initialise the project environment." >&2
  exit 1
fi

BENCH_DIR="${BENCH_DIR:-$ROOT_DIR/frappe-bench}"
export BENCH_DIR
if [[ ! -d "$BENCH_DIR" ]]; then
  echo "Frappe bench not found at: $BENCH_DIR" >&2
  echo "Run ./install.sh to provision the bench before setting up the pipeline." >&2
  exit 1
fi

exec bash "$ROOT_DIR/bootstrap/install-development-pipeline.sh" "$@"
