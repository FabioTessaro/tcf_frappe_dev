#!/bin/bash
set -e

# Work relative to this script's location, so it behaves the same regardless
# of the caller's current directory.
cd "$(dirname "$0")"

usage() {
  cat << EOF
Usage: ./reseed.sh [options]

Re-downloads the VS Code Server build and copies it into the frappe
container again (see bootstrap/setup-vscode.sh for how this works). Use it
when "Attach to Running Container" hangs, the server inside the container is
broken or half-copied, or your VS Code client updated and no longer matches.

With no options, shows an interactive menu. Options (for non-interactive use):

  --auto              Re-seed using the commit auto-detected from the host
                      (or the container's leftover folders), falling back to
                      the latest stable. This is the menu's default.
  --latest            Ignore detection, use the latest stable release for
                      your client's platform (see --platform).
  --commit <hash>     Re-seed this exact 40-character commit. Find it in
                      VS Code: Help > About > "Commit".
  --platform <name>   Local client platform for --latest. One of:
                      win32-x64 win32-arm64 darwin-x64 darwin-arm64
                      linux-x64 linux-arm64 server-linux-x64
  --purge             Also delete every other VS Code Server build inside the
                      container afterwards (frees disk; breaks any window
                      currently attached using another build).
  -y, --yes           Don't ask for confirmation.
  -h, --help          Show this help.

Examples:
  ./reseed.sh
  ./reseed.sh --commit 0123456789abcdef0123456789abcdef01234567 -y
  ./reseed.sh --latest --platform darwin-arm64 --purge
EOF
}

# --- parse flags -----------------------------------------------------------
MODE=""            # auto | latest | commit  (empty = ask interactively)
COMMIT=""
PLATFORM=""
PURGE=false
ASSUME_YES=false

while [ $# -gt 0 ]; do
  case "$1" in
    --auto) MODE="auto" ;;
    --latest) MODE="latest" ;;
    --commit)
      if [ $# -lt 2 ]; then echo "--commit needs a value"; exit 2; fi
      MODE="commit"; COMMIT="$2"; shift ;;
    --commit=*) MODE="commit"; COMMIT="${1#*=}" ;;
    --platform)
      if [ $# -lt 2 ]; then echo "--platform needs a value"; exit 2; fi
      PLATFORM="$2"; shift ;;
    --platform=*) PLATFORM="${1#*=}" ;;
    --purge) PURGE=true ;;
    -y|--yes) ASSUME_YES=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

source bootstrap/lib.sh

if ! $DOCKER_COMPOSE exec -T frappe true >/dev/null 2>&1; then
  echo "The frappe container isn't running. Start it first (./startup.sh),"
  echo "then run ./reseed.sh again."
  exit 1
fi

# --- helpers ---------------------------------------------------------------
normalize_commit() {
  echo "$1" | tr -d '[:space:]' | tr 'A-F' 'a-f'
}

is_valid_commit() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

detect_host_commit() {
  local h=""
  if [ -d "$HOME/.vscode-server/cli/servers" ]; then
    h=$(ls -t "$HOME/.vscode-server/cli/servers" 2>/dev/null \
      | grep -m1 '^Stable-' | sed 's/^Stable-//' || true)
  fi
  if [ -z "$h" ] && [ -d "$HOME/.vscode-server/bin" ]; then
    h=$(ls -t "$HOME/.vscode-server/bin" 2>/dev/null \
      | grep -m1 -E '^[0-9a-f]{40}$' || true)
  fi
  echo "$h"
}

list_container_builds() {
  $DOCKER_COMPOSE exec -T frappe sh -c \
    "ls -1t /home/frappe/.vscode-server/bin/ 2>/dev/null" || true
}

pick_platform() {
  echo ""
  echo "Which platform does your LOCAL VS Code client run on?"
  echo "  1) Windows x64"
  echo "  2) Windows ARM64"
  echo "  3) macOS Intel"
  echo "  4) macOS Apple Silicon"
  echo "  5) Linux x64"
  echo "  6) Linux ARM64"
  echo "  7) Not sure — use the Linux server build's own latest"
  read -r -p "Choice [1-7, default 7]: " c
  case "$c" in
    1) PLATFORM="win32-x64" ;;
    2) PLATFORM="win32-arm64" ;;
    3) PLATFORM="darwin-x64" ;;
    4) PLATFORM="darwin-arm64" ;;
    5) PLATFORM="linux-x64" ;;
    6) PLATFORM="linux-arm64" ;;
    *) PLATFORM="server-linux-x64" ;;
  esac
}

# --- interactive menu ------------------------------------------------------
if [ -z "$MODE" ]; then
  if [ ! -t 0 ]; then
    # No TTY and no flags: don't hang on a prompt, just do the default.
    MODE="auto"
  else
    HOST_COMMIT=$(detect_host_commit)
    echo "VS Code Server re-seed"
    echo "----------------------"
    echo "Host-detected commit:  ${HOST_COMMIT:-(none — no VS Code connection to this host yet)}"
    echo "Builds in container:"
    BUILDS=$(list_container_builds)
    if [ -n "$BUILDS" ]; then
      echo "$BUILDS" | sed 's/^/                       /'
    else
      echo "                       (none)"
    fi
    echo ""
    echo "What do you want to do?"
    echo "  1) Re-seed the auto-detected commit            [default]"
    echo "  2) Re-seed the latest stable release (pick your client platform)"
    echo "  3) Re-seed a specific commit (paste it)"
    echo "  4) Cancel"
    read -r -p "Choice [1-4, default 1]: " CHOICE
    case "$CHOICE" in
      ""|1) MODE="auto" ;;
      2) MODE="latest" ;;
      3) MODE="commit" ;;
      *) echo "Cancelled."; exit 0 ;;
    esac

    if [ "$MODE" = "latest" ] && [ -z "$PLATFORM" ]; then
      pick_platform
    fi

    if [ "$MODE" = "commit" ] && [ -z "$COMMIT" ]; then
      echo ""
      echo "Paste the 40-character commit hash (VS Code: Help > About > Commit)."
      read -r -p "Commit: " COMMIT
    fi

    if [ "$PURGE" = false ]; then
      echo ""
      read -r -p "Also delete all OTHER builds in the container? [y/N]: " P
      case "$P" in y|Y|yes|YES) PURGE=true ;; esac
    fi
  fi
fi

# --- validate --------------------------------------------------------------
if [ "$MODE" = "commit" ]; then
  COMMIT=$(normalize_commit "$COMMIT")
  if ! is_valid_commit "$COMMIT"; then
    echo "'$COMMIT' isn't a valid commit hash (expected 40 hex characters)."
    exit 1
  fi
fi

# --- build the setup-vscode.sh invocation ----------------------------------
ARGS=(--reseed)
DESC=""
case "$MODE" in
  auto)
    DESC="auto-detected commit (falls back to latest stable)" ;;
  latest)
    ARGS+=(--latest)
    [ -n "$PLATFORM" ] && ARGS+=(--platform "$PLATFORM")
    DESC="latest stable${PLATFORM:+ for $PLATFORM}" ;;
  commit)
    ARGS+=(--commit "$COMMIT")
    DESC="commit $COMMIT" ;;
esac
if [ "$PURGE" = true ]; then
  ARGS+=(--purge)
  DESC="$DESC, purging other builds"
fi

# --- confirm ---------------------------------------------------------------
echo ""
echo "About to re-seed the frappe container with: $DESC"
echo "If a VS Code window is currently attached to the container, reload it"
echo "afterwards (Developer: Reload Window)."
if [ "$ASSUME_YES" = false ] && [ -t 0 ]; then
  read -r -p "Continue? [Y/n]: " OK
  case "$OK" in n|N|no|NO) echo "Cancelled."; exit 0 ;; esac
fi

echo ""
bash bootstrap/setup-vscode.sh "${ARGS[@]}"