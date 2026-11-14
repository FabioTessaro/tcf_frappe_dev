#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Dev Containers postCreateCommand: provision bench first, then the frontend toolchain.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"
export PATH="$HOME/.local/bin:$PATH"

bash bootstrap/install-system-dependencies.sh
bash bootstrap/provision-bench.sh -y
bash ./setup-env.sh --skip-system-tools --defer-app-selection
