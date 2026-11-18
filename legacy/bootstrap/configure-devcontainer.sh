#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Render the checked-in Dev Container configuration template.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/template-lib.sh"

render_template \
  "$SCRIPT_DIR/templates/devcontainer.json.template" \
  "$ROOT_DIR/.devcontainer/devcontainer.json"
