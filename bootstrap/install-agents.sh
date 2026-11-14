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
# ARCH="$(uname -m)"

# --- Ensure Local Bin Directory & PATH -----------------------------------
# Create directory if missing and load into current script session
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Ensure Claude's configuration and download directories belong to
# the current user. A previous installation may have created them as root.
ensure_claude_directories() {
  local claude_dir="$HOME/.claude"
  local downloads_dir="$claude_dir/downloads"
  local owner
  owner="$(id -u):$(id -g)"

  if [[ -L "$claude_dir" || ( -e "$claude_dir" && ! -d "$claude_dir" ) ]]; then
    log_error "Invalid Claude configuration path: $claude_dir"
    return 1
  fi

  if [[ -d "$claude_dir" && ! -O "$claude_dir" ]]; then
    echo "Claude directory has incorrect ownership; repairing..."
    if ! command -v sudo >/dev/null 2>&1 ||
       ! sudo chown -R "$owner" "$claude_dir"; then
      log_error "Could not repair ownership of $claude_dir."
      return 1
    fi
  fi

  if ! mkdir -p "$downloads_dir"; then
    log_error "Could not create $downloads_dir."
    return 1
  fi

  if [[ ! -O "$downloads_dir" ]]; then
    echo "Claude downloads directory has incorrect ownership; repairing..."
    if ! sudo chown -R "$owner" "$claude_dir"; then
      log_error "Could not repair ownership of $claude_dir."
      return 1
    fi
  fi

  chmod 700 "$claude_dir" "$downloads_dir" || return 1
}

# Persist PATH in ~/.bashrc if not already present
append_template_block "$SCRIPT_DIR/templates/local-bin-path.block.template" "$HOME/.bashrc" "BEGIN TCF DEVELOPMENT USER BIN PATH"

# --- Claude Code ---------------------------------------------------------
if command -v claude &> /dev/null; then
  echo "Claude Code already installed ($(claude --version 2>/dev/null))."
elif ensure_claude_directories; then
  echo "Installing Claude Code..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    echo "Claude Code installed."
  else
    echo "Claude Code installation failed. Check the installer output and internet access."
  fi
else
  echo "Claude Code installation skipped because its directories could not be prepared."
fi

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "NOTE: ~/.local/bin isn't on PATH in this shell. Open a new terminal"
  echo "(or 'source ~/.bashrc') and 'claude'/'codex' should resolve. If not,"
  echo "add this to ~/.bashrc:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
