#!/bin/bash
# Installs the Claude Code CLI (Architect) and OpenAI Codex CLI (Executor)
# inside the frappe container. Both ship as self-contained native binaries,
# so neither depends on the Node.js version frappe/bench:latest bundles for
# building Frappe's own frontend assets. Safe to re-run: skips whichever
# tool is already installed.

set -u
# No "set -e" for the same reason as setup-vscode.sh: a failed download here
# (no outbound internet to Anthropic/GitHub) shouldn't abort install.sh or
# startup.sh as a whole — just skip and let it be retried by hand.

ARCH="$(uname -m)"

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

echo ""
echo "Creating claude settings.json to restrict destructive commands..."
mkdir -p .claude
cat > .claude/settings.json <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [],
    "deny": []
  }
}
EOF
echo "Claude Code settings.json created."

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "NOTE: ~/.local/bin isn't on PATH in this shell. Open a new terminal"
  echo "(or 'source ~/.bashrc') and 'claude'/'codex' should resolve. If not,"
  echo "add this to ~/.bashrc:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi