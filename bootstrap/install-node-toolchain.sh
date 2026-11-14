#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Install a user-local, pinned Node.js major and activate Corepack/pnpm.
set -euo pipefail

NODE_VERSION="${NODE_VERSION:-26}"
NVM_VERSION="${NVM_VERSION:-v0.40.3}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
export NVM_DIR
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/template-lib.sh"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  command -v curl >/dev/null 2>&1 || { echo "curl is required to install nvm." >&2; exit 1; }
  echo "Installing nvm $NVM_VERSION for $USER..."
  tmp_file=$(mktemp)
  trap 'rm -f "$tmp_file"' EXIT
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" -o "$tmp_file"
  PROFILE=/dev/null bash "$tmp_file"
  rm -f "$tmp_file"
  trap - EXIT
fi

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "nvm installation did not create $NVM_DIR/nvm.sh." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"

nvm install "$NODE_VERSION"
nvm alias default "$NODE_VERSION" >/dev/null
nvm use "$NODE_VERSION" >/dev/null

# Persist nvm activation in interactive and login shells through a template.
for profile_file in "$HOME/.bashrc" "$HOME/.profile"; do
  append_template_block "$SCRIPT_DIR/templates/nvm-profile.block.template" "$profile_file" "BEGIN TCF DEVELOPMENT NODE TOOLCHAIN"
done

if ! command -v corepack >/dev/null 2>&1; then
  echo "Installing Corepack (not bundled in every Node.js distribution)..."
  npm install --global corepack@latest
fi
corepack enable
corepack prepare pnpm@latest --activate

printf '\nNode.js: %s\n' "$(node --version)"
printf 'npm:     %s\n' "$(npm --version)"
printf 'Corepack:%s\n' "$(corepack --version)"
printf 'pnpm:    %s\n' "$(pnpm --version)"
