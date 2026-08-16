#!/bin/bash
set -e

echo "=== Git identity + SSH setup ==="

# --- git installed? ---
if ! command -v git &> /dev/null; then
  echo "git not found — installing..."
  sudo apt update && sudo apt install -y git
fi

# --- git user.name / user.email ---
CURRENT_NAME=$(git config --global user.name || true)
CURRENT_EMAIL=$(git config --global user.email || true)

if [ -n "$CURRENT_NAME" ] && [ -n "$CURRENT_EMAIL" ]; then
  echo "Git identity already set: $CURRENT_NAME <$CURRENT_EMAIL>"
  read -p "Keep this identity? (y/n): " KEEP
  if [ "$KEEP" != "y" ]; then
    CURRENT_NAME=""
    CURRENT_EMAIL=""
  fi
fi

if [ -z "$CURRENT_NAME" ]; then
  read -p "Enter your git username: " GIT_NAME
  git config --global user.name "$GIT_NAME"
fi

if [ -z "$CURRENT_EMAIL" ]; then
  read -p "Enter your git email: " GIT_EMAIL
  git config --global user.email "$GIT_EMAIL"
fi

# --- SSH key: check for a genuinely valid one, not just a file that exists ---
# (a file existing but empty/corrupted is exactly what caused the earlier
# "Permission denied (publickey)" — detection has to actually validate it)
KEY_PATH="$HOME/.ssh/id_ed25519"
HAVE_VALID_KEY=false

if [ -f "$KEY_PATH" ] && ssh-keygen -l -f "$KEY_PATH" &> /dev/null; then
  HAVE_VALID_KEY=true
  echo "Existing valid SSH key found at $KEY_PATH."
fi

if [ "$HAVE_VALID_KEY" = false ]; then
  echo "No valid SSH key found — generating one."
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$KEY_PATH"
fi

# --- Fix permissions regardless — cheap insurance against the same bug ---
chmod 700 "$HOME/.ssh"
chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub"

eval "$(ssh-agent -s)" &> /dev/null
ssh-add "$KEY_PATH" &> /dev/null

# --- Verify against GitHub; if it fails, walk the user through adding it ---
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo "SSH key already works with GitHub."
else
  echo ""
  echo "This key isn't registered with GitHub yet. Add it now:"
  echo "  1. Copy the key below"
  echo "  2. Go to https://github.com/settings/ssh/new"
  echo "  3. Set Key type to 'Authentication Key', paste, and save"
  echo ""
  echo "--------------------------------------------------------------"
  cat "$KEY_PATH.pub"
  echo "--------------------------------------------------------------"
  echo ""
  read -p "Press Enter once you've added it to GitHub..." _

  until ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; do
    echo "Still not authenticating. Double-check it was saved as an Authentication Key, then:"
    read -p "Press Enter to retry..." _
  done
  echo "SSH key verified with GitHub."
fi

echo "=== Git setup complete ==="