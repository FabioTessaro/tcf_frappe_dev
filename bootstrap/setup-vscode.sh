#!/bin/bash
# Pre-seeds the VS Code Server build inside the frappe container so that
# "Dev Containers: Attach to Running Container" doesn't have to stream the
# ~200MB server tarball live through docker exec's stdin — a path that's
# proven to hang intermittently on this Docker Engine version. Instead this
# script fetches the tarball with a plain curl (proven reliable) and copies
# it in directly.
#
# The exact VS Code Server build needed is tied to YOUR LOCAL VS Code
# client's commit hash, not this repo — so there is nothing to hardcode.
# This script auto-detects it from what your client has already negotiated
# with this machine, checked in this order:
#   1. ~/.vscode-server/cli/servers/Stable-<hash>/  — the lightweight "CLI"
#      runtime your plain Remote-SSH connection installs on the VM host as
#      soon as you've SSH'd in from VS Code even once (container or not).
#   2. ~/.vscode-server/bin/<hash>/                 — classic-layout host
#      install, if your client used that instead.
#   3. A leftover partial/temp folder inside the frappe container itself
#      (.vscode-server/bin/<hash>_<timestamp>), left behind by a previous
#      hung attach attempt.
#   4. LAST RESORT: if none of the above exist — you've truly never
#      connected with VS Code to this machine — this script asks which
#      platform your LOCAL VS Code client runs on (Windows/macOS/Linux),
#      queries Microsoft's update API for whatever is CURRENTLY latest
#      stable on *that* platform, and pre-seeds the matching Linux server
#      build for that same commit. Stable releases are normally built from
#      one commit shared across every platform, but staged rollouts can
#      briefly put platforms out of sync — asking narrows the guess to
#      the release your client would actually be offered. This is still
#      not a guarantee (custom/OEM VS Code builds in particular can trail
#      the public "stable" release entirely), so it's clearly logged as an
#      unconfirmed guess, not a certainty. Your platform choice is cached
#      in bootstrap/.vscode-platform so you're only asked once.
#
# Steps 1-3 always take priority over the step 4 guess on every run, and
# the pre-seed check is keyed to the exact hash's own folder — so as soon
# as a REAL connection creates a folder matching steps 1-3, the next
# install.sh/startup.sh run detects that confirmed hash, sees it doesn't
# match whatever was guessed, and re-seeds the correct one automatically.
# No manual cleanup or state tracking needed.
#
# If even step 4 fails (no internet route to Microsoft's CDN), the script
# skips quietly; the next attach attempt behaves as before this fix existed
# (it may hang once — retry it or re-run this script).

set -u
# Deliberately no "set -e": this is a best-effort convenience step and must
# never fail install.sh/startup.sh as a whole just because, say, this VM
# has no outbound internet access to Microsoft's CDN.

cd "$(dirname "$0")/.."
source bootstrap/lib.sh

echo "Checking whether the VS Code Server needs pre-seeding..."

HASH=""
CONFIRMED=true

# 1. Newer "CLI" layout on the host (created by plain Remote-SSH too)
if [ -d "$HOME/.vscode-server/cli/servers" ]; then
  HASH=$(ls -t "$HOME/.vscode-server/cli/servers" 2>/dev/null \
    | grep -m1 '^Stable-' | sed 's/^Stable-//')
fi

# 2. Classic layout on the host
if [ -z "$HASH" ] && [ -d "$HOME/.vscode-server/bin" ]; then
  HASH=$(ls -t "$HOME/.vscode-server/bin" 2>/dev/null \
    | grep -m1 -E '^[0-9a-f]{40}$')
fi

# 3. Leftover partial folder inside the container from a previous hung attach
if [ -z "$HASH" ]; then
  HASH=$($DOCKER_COMPOSE exec -T frappe sh -c \
    "ls -t /home/frappe/.vscode-server/bin/ 2>/dev/null" \
    | grep -m1 -E '^[0-9a-f]{40}(_[0-9]+)?$' | sed -E 's/_[0-9]+$//')
fi

# 4. Last resort: ask which platform your LOCAL client runs on, look up
# that platform's current latest stable, and use its commit hash. Not
# necessarily correct for your specific client (see notes above) — but
# gives a real chance of working instead of guaranteeing a hang, and will
# self-correct once a real connection is detected on a future run.
if [ -z "$HASH" ]; then
  PLATFORM_CACHE="bootstrap/.vscode-platform"
  QUERY_PLATFORM=""

  if [ -f "$PLATFORM_CACHE" ]; then
    QUERY_PLATFORM=$(cat "$PLATFORM_CACHE")
  elif [ -t 0 ]; then
    echo ""
    echo "No VS Code connection detected yet, so the build to pre-seed has"
    echo "to be guessed. Which platform does your LOCAL VS Code client run"
    echo "on? (Stable releases can roll out to platforms at slightly"
    echo "different times, so this narrows the guess.)"
    echo "  1) Windows x64"
    echo "  2) Windows ARM64"
    echo "  3) macOS Intel"
    echo "  4) macOS Apple Silicon"
    echo "  5) Linux x64"
    echo "  6) Linux ARM64"
    echo "  7) Not sure / skip — use the Linux server build's own latest"
    read -r -p "Choice [1-7, default 7]: " PLATFORM_CHOICE
    case "$PLATFORM_CHOICE" in
      1) QUERY_PLATFORM="win32-x64" ;;
      2) QUERY_PLATFORM="win32-arm64" ;;
      3) QUERY_PLATFORM="darwin-x64" ;;
      4) QUERY_PLATFORM="darwin-arm64" ;;
      5) QUERY_PLATFORM="linux-x64" ;;
      6) QUERY_PLATFORM="linux-arm64" ;;
      *) QUERY_PLATFORM="server-linux-x64" ;;
    esac
    echo "$QUERY_PLATFORM" > "$PLATFORM_CACHE"
  else
    # Non-interactive (no TTY) — don't hang waiting on input, just fall
    # back to asking the Linux server platform about itself, as before.
    QUERY_PLATFORM="server-linux-x64"
  fi

  LATEST_JSON=$(curl -fsSL "https://update.code.visualstudio.com/api/latest/$QUERY_PLATFORM/stable" 2>/dev/null)
  HASH=$(echo "$LATEST_JSON" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 | sed -E 's/.*"([0-9a-f]{40})".*/\1/')
  if [ -n "$HASH" ]; then
    CONFIRMED=false
  fi
fi

if [ -z "$HASH" ]; then
  echo "No VS Code commit hash detected, and the latest-stable API lookup"
  echo "also failed (check internet access) — skipping pre-seed."
  exit 0
fi

if [ "$CONFIRMED" = true ]; then
  echo "Detected VS Code Server commit: $HASH"
else
  echo "No confirmed VS Code connection found yet — guessing based on"
  echo "$QUERY_PLATFORM's current latest stable release: $HASH"
  echo "This is unconfirmed. If your actual client uses a different build,"
  echo "attach may still need to fetch it once; this script will pick up"
  echo "and switch to the correct hash automatically on its next run after"
  echo "you've connected for real."
fi

TARGET="/home/frappe/.vscode-server/bin/$HASH"

if $DOCKER_COMPOSE exec -T frappe test -f "$TARGET/product.json" 2>/dev/null; then
  echo "Already pre-seeded for commit $HASH — nothing to do."
  exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading VS Code Server build for $HASH..."
if ! curl -fsSL -o "$TMP_DIR/vscode-server.tar.gz" \
    "https://update.code.visualstudio.com/commit:$HASH/server-linux-x64/stable"; then
  echo "Download failed — skipping pre-seed. The first attach attempt may"
  echo "need to fetch it live instead (which may hang; retry if so)."
  exit 0
fi

mkdir -p "$TMP_DIR/extracted"
tar -xzf "$TMP_DIR/vscode-server.tar.gz" -C "$TMP_DIR/extracted"

# The tarball may extract straight into files, or into a single wrapping
# subfolder depending on how it was packaged — handle both so we always
# copy the right level into the container.
SRC="$TMP_DIR/extracted"
ENTRIES=$(find "$SRC" -mindepth 1 -maxdepth 1)
if [ "$(echo "$ENTRIES" | wc -l)" -eq 1 ] && [ -d "$ENTRIES" ]; then
  SRC="$ENTRIES"
fi

echo "Copying into the frappe container..."
$DOCKER_COMPOSE exec -T -u root frappe mkdir -p "$TARGET"
$DOCKER_COMPOSE cp "$SRC/." "frappe:$TARGET/"
$DOCKER_COMPOSE exec -T -u root frappe chown -R frappe:frappe /home/frappe/.vscode-server

if [ "$CONFIRMED" = true ]; then
  echo "Pre-seed complete for commit $HASH — attach should connect instantly now."
else
  echo "Pre-seeded a guessed build ($HASH) since no confirmed VS Code"
  echo "connection has been detected yet. Attach may still work fine — but"
  echo "if it doesn't match your real client, this corrects itself"
  echo "automatically the next time install.sh/startup.sh runs after a real"
  echo "connection."
fi
