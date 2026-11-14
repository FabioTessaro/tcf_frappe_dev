#!/usr/bin/env bash
# Generate the workspace and install extensions when a VS Code Server CLI is available.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

if [[ -f .env && -d frappe-bench ]]; then
  bash bootstrap/configure-workspace.sh
else
  echo "Skipping workspace generation: .env or frappe-bench is not present yet."
fi

if [[ -f .pre-commit-config.yaml ]] && command -v pre-commit >/dev/null 2>&1; then
  pre-commit install
else
  echo "No root pre-commit configuration found; leaving Git hooks unchanged."
fi

echo "Development tooling configuration complete."
