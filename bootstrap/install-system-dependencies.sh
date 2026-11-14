#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Install operating-system tools needed by the Frappe + frontend toolchain.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/pipeline-common.sh
source "$SCRIPT_DIR/pipeline-common.sh"
source "$SCRIPT_DIR/template-lib.sh"

as_root() {
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Root privileges are required to install system packages (sudo unavailable)." >&2
    return 1
  fi
}

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the container OS (/etc/os-release missing)." >&2
  exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" && "${ID:-}" != "debian" && "${ID_LIKE:-}" != *debian* ]]; then
  echo "Unsupported container OS: ${PRETTY_NAME:-${ID:-unknown}}. This installer currently supports Debian/Ubuntu." >&2
  exit 1
fi

PACKAGES=(
  ca-certificates curl git jq iproute2 mariadb-client redis-tools unzip
  procps build-essential python3-dev libffi-dev libssl-dev libatomic1
)

missing=false
if ! command -v dpkg-query >/dev/null 2>&1; then
  missing=true
else
  for package in "${PACKAGES[@]}"; do
    package_status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
    if [[ "$package_status" != "installed" ]]; then
      missing=true
      break
    fi
  done
fi

if [[ "$missing" == true ]]; then
  echo "Installing required Debian/Ubuntu packages..."
  as_root apt-get update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PACKAGES[@]}"
else
  echo "System command prerequisites are already present; skipping apt installation."
fi

export PATH="$HOME/.local/bin:$PATH"
for profile_file in "$HOME/.bashrc" "$HOME/.profile"; do
  append_template_block "$SCRIPT_DIR/templates/local-bin-path.block.template" "$profile_file" "BEGIN TCF DEVELOPMENT USER BIN PATH"
done

if ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv for the current user..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || { echo "uv installation failed." >&2; exit 1; }

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "Installing pre-commit with uv..."
  uv tool install pre-commit
  export PATH="$(uv tool dir --bin 2>/dev/null || printf '%s' "$HOME/.local/bin"):$PATH"
fi
command -v pre-commit >/dev/null 2>&1 || { echo "pre-commit installation failed or its executable is not on PATH." >&2; exit 1; }

echo "System toolchain prerequisites are ready."
