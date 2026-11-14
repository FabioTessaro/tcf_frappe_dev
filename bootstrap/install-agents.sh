#!/bin/bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Installs the Claude Code CLI (Architect) and OpenAI Codex CLI (Executor)
# inside the frappe container. Both ship as self-contained native binaries,
# so neither depends on the Node.js version frappe/bench:latest bundles for
# building Frappe's own frontend assets. Safe to re-run: skips whichever
# tool is already installed.

set -u
# No "set -e" for the same reason as seed-vscode-server.sh: a failed download here
# (no outbound internet to Anthropic/GitHub) shouldn't abort install.sh or
# startup.sh as a whole — just skip and let it be retried by hand.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/template-lib.sh"
ARCH="$(uname -m)"

# --- Ensure Local Bin Directory & PATH -----------------------------------
# Create directory if missing and load into current script session
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Persist PATH in ~/.bashrc if not already present
append_template_block "$SCRIPT_DIR/templates/local-bin-path.block.template" "$HOME/.bashrc" "BEGIN TCF DEVELOPMENT USER BIN PATH"

# --- Claude Code ---------------------------------------------------------
if command -v claude &> /dev/null; then
  echo "Claude Code already installed ($(claude --version 2>/dev/null))."
else
  echo "Installing Claude Code..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    echo "Claude Code installed."
  else
    echo "Claude Code install failed — check internet access. Skipping."
  fi
fi

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "NOTE: ~/.local/bin isn't on PATH in this shell. Open a new terminal"
  echo "(or 'source ~/.bashrc') and 'claude'/'codex' should resolve. If not,"
  echo "add this to ~/.bashrc:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi