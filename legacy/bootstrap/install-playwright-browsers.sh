#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Install Chromium and its Linux runtime dependencies for the core E2E suite.
set -euo pipefail

FRONTEND_DIR="${1:-${FRONTEND_DIR:-}}"
if [[ -z "$FRONTEND_DIR" || ! -f "$FRONTEND_DIR/package.json" ]]; then
  echo "Usage: $0 <core-frontend-directory> (with package.json installed)" >&2
  exit 2
fi

cd "$FRONTEND_DIR"
if ! pnpm exec playwright --version >/dev/null 2>&1; then
  echo "Playwright is not installed in $FRONTEND_DIR. Add @playwright/test and rerun install-frontend-dependencies.sh." >&2
  exit 1
fi

if pnpm exec playwright install --list 2>/dev/null | grep -qi chromium; then
  echo "Playwright Chromium is already installed; skipping browser and OS dependency downloads."
else
  if [[ "$EUID" -eq 0 ]]; then
    pnpm exec playwright install-deps chromium
  elif command -v sudo >/dev/null 2>&1; then
    # Preserve the user-local Node/Corepack binaries and frontend working path
    # while running only Playwright's apt dependency installation as root.
    sudo env "PATH=$PATH" "HOME=$HOME" pnpm exec playwright install-deps chromium
  else
    echo "Playwright's Linux dependencies require root privileges; install them with sudo or run as root." >&2
    exit 1
  fi

  pnpm exec playwright install chromium
fi

if ! pnpm exec playwright install --list 2>/dev/null | grep -qi chromium; then
  echo "Playwright Chromium installation could not be verified." >&2
  exit 1
fi

echo "Playwright Chromium is ready for $FRONTEND_DIR."
