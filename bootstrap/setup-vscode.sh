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
#
# ---------------------------------------------------------------------------
# RE-SEED MODE (--reseed)
# ---------------------------------------------------------------------------
# Normally, if the container already has the build for the detected hash,
# this script does nothing. Re-seed mode is for when that build is broken,
# half-copied, or simply the wrong one (e.g. your VS Code client updated):
# it deletes the target build inside the container and downloads/copies it
# again. Most people should use ./reseed.sh, which wraps this script with
# an interactive menu. Flags (all optional, combinable):
#
#   --reseed            Force re-download and re-copy even if the build is
#                       already present (existing copy is removed first).
#                       Also makes failures exit non-zero instead of
#                       skipping quietly.
#   --commit <hash>     Seed this exact 40-char commit (Help > About in VS
#                       Code shows it). Skips all auto-detection.
#   --latest            Skip steps 1-3 and use step 4 (latest stable for
#                       your client's platform) even if a host/container
#                       hash was detected.
#   --platform <name>   Platform to query in step 4 (also cached). One of:
#                       win32-x64 win32-arm64 darwin-x64 darwin-arm64
#                       linux-x64 linux-arm64 server-linux-x64
#   --ask-platform      Ignore the cached platform and ask again (step 4).
#   --purge             After seeding, delete every OTHER build under
#                       /home/frappe/.vscode-server/bin in the container.
#                       Any VS Code window attached to the container using
#                       one of those builds will break until reloaded.
#   -h, --help          Show this summary.

set -u
# Deliberately no "set -e": this is a best-effort convenience step and must
# never fail install.sh/startup.sh as a whole just because, say, this VM
# has no outbound internet access to Microsoft's CDN. (Re-seed mode is the
# exception: there the user asked for this explicitly, so failures return a
# non-zero exit code.)

VALID_PLATFORMS="win32-x64 win32-arm64 darwin-x64 darwin-arm64 linux-x64 linux-arm64 server-linux-x64"

usage() {
  cat << EOF
Usage: bootstrap/setup-vscode.sh [options]

  --reseed            Force re-download/re-copy even if already present
  --commit <hash>     Seed this exact 40-char VS Code commit
  --latest            Skip host/container detection; use latest stable
  --platform <name>   Platform for the latest-stable lookup (cached):
                      $VALID_PLATFORMS
  --ask-platform      Ignore the cached platform and ask again
  --purge             Delete all other builds in the container afterwards
  -h, --help          Show this help
EOF
}

RESEED=false
CUSTOM_COMMIT=""
FORCE_LATEST=false
CLI_PLATFORM=""
ASK_PLATFORM=false
PURGE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --reseed) RESEED=true ;;
    --latest) FORCE_LATEST=true ;;
    --ask-platform) ASK_PLATFORM=true ;;
    --purge) PURGE=true ;;
    --commit)
      if [ $# -lt 2 ]; then echo "--commit needs a value"; exit 2; fi
      CUSTOM_COMMIT="$2"; shift ;;
    --commit=*) CUSTOM_COMMIT="${1#*=}" ;;
    --platform)
      if [ $# -lt 2 ]; then echo "--platform needs a value"; exit 2; fi
      CLI_PLATFORM="$2"; shift ;;
    --platform=*) CLI_PLATFORM="${1#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

# Exit code used when we have to give up: quiet success for the automatic
# install/startup path, a real failure when the user explicitly re-seeds.
if [ "$RESEED" = true ]; then GIVE_UP_RC=1; else GIVE_UP_RC=0; fi

cd "$(dirname "$0")/.."
source bootstrap/lib.sh

echo "Checking whether the VS Code Server needs pre-seeding..."

# The frappe container has to be up for any of this to work.
if ! $DOCKER_COMPOSE exec -T frappe true >/dev/null 2>&1; then
  echo "The frappe container isn't running — can't pre-seed. Start it first"
  echo "(./startup.sh) and run this again."
  exit $GIVE_UP_RC
fi

ask_platform() {
  # Prompts for the local client platform; sets QUERY_PLATFORM.
  echo ""
  echo "Which platform does your LOCAL VS Code client run on? (Stable"
  echo "releases can roll out to platforms at slightly different times,"
  echo "so this narrows the guess.)"
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
}

purge_others() {
  # Removes every build in the container's .vscode-server/bin except $HASH.
  echo "Purging other VS Code Server builds inside the container..."
  $DOCKER_COMPOSE exec -T -u root frappe sh -c \
    "find /home/frappe/.vscode-server/bin -mindepth 1 -maxdepth 1 ! -name '$HASH' -exec rm -rf {} + 2>/dev/null; true"
}

HASH=""
CONFIRMED=true
SOURCE="detected"
QUERY_PLATFORM=""

if [ -n "$CUSTOM_COMMIT" ]; then
  # --commit: the user told us exactly what they want. No detection.
  CUSTOM_COMMIT=$(echo "$CUSTOM_COMMIT" | tr -d '[:space:]' | tr 'A-F' 'a-f')
  if ! [[ "$CUSTOM_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "'$CUSTOM_COMMIT' isn't a valid VS Code commit hash (expected 40"
    echo "hex characters — see Help > About in VS Code)."
    exit 2
  fi
  HASH="$CUSTOM_COMMIT"
  SOURCE="custom"
fi

if [ -z "$HASH" ] && [ "$FORCE_LATEST" = false ]; then
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
fi

# 4. Last resort (or forced with --latest): ask which platform your LOCAL
# client runs on, look up that platform's current latest stable, and use its
# commit hash. Not necessarily correct for your specific client (see notes
# above) — but gives a real chance of working instead of guaranteeing a
# hang, and will self-correct once a real connection is detected on a
# future run.
if [ -z "$HASH" ]; then
  PLATFORM_CACHE="bootstrap/.vscode-platform"

  if [ -n "$CLI_PLATFORM" ]; then
    if ! echo " $VALID_PLATFORMS " | grep -q " $CLI_PLATFORM "; then
      echo "Unknown platform '$CLI_PLATFORM'. Valid: $VALID_PLATFORMS"
      exit 2
    fi
    QUERY_PLATFORM="$CLI_PLATFORM"
    echo "$QUERY_PLATFORM" > "$PLATFORM_CACHE"
  elif [ "$ASK_PLATFORM" = false ] && [ -f "$PLATFORM_CACHE" ]; then
    QUERY_PLATFORM=$(cat "$PLATFORM_CACHE")
  elif [ -t 0 ]; then
    ask_platform
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
    SOURCE="latest"
  fi
fi

if [ -z "$HASH" ]; then
  echo "No VS Code commit hash detected, and the latest-stable API lookup"
  echo "also failed (check internet access) — skipping pre-seed."
  exit $GIVE_UP_RC
fi

case "$SOURCE" in
  custom)
    echo "Using the VS Code Server commit you specified: $HASH" ;;
  detected)
    echo "Detected VS Code Server commit: $HASH" ;;
  latest)
    echo "No confirmed VS Code connection used — guessing based on"
    echo "$QUERY_PLATFORM's current latest stable release: $HASH"
    echo "This is unconfirmed. If your actual client uses a different build,"
    echo "attach may still need to fetch it once; this script will pick up"
    echo "and switch to the correct hash automatically on its next run after"
    echo "you've connected for real." ;;
esac

TARGET="/home/frappe/.vscode-server/bin/$HASH"

if $DOCKER_COMPOSE exec -T frappe test -f "$TARGET/product.json" 2>/dev/null; then
  if [ "$RESEED" = false ]; then
    echo "Already pre-seeded for commit $HASH — nothing to do."
    [ "$PURGE" = true ] && purge_others
    exit 0
  fi
  echo "Build for commit $HASH is already present — re-seeding anyway (--reseed)."
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading VS Code Server build for $HASH..."
if ! curl -fsSL -o "$TMP_DIR/vscode-server.tar.gz" \
    "https://update.code.visualstudio.com/commit:$HASH/server-linux-x64/stable"; then
  if [ "$SOURCE" = "custom" ]; then
    echo "Download failed — Microsoft's CDN doesn't have a build for that"
    echo "commit (typo?) or there's no internet route to it."
  else
    echo "Download failed — skipping pre-seed. The first attach attempt may"
    echo "need to fetch it live instead (which may hang; retry if so)."
  fi
  exit $GIVE_UP_RC
fi

mkdir -p "$TMP_DIR/extracted"
if ! tar -xzf "$TMP_DIR/vscode-server.tar.gz" -C "$TMP_DIR/extracted"; then
  echo "The downloaded archive couldn't be extracted (corrupt download?)."
  exit $GIVE_UP_RC
fi

# The tarball may extract straight into files, or into a single wrapping
# subfolder depending on how it was packaged — handle both so we always
# copy the right level into the container.
SRC="$TMP_DIR/extracted"
ENTRIES=$(find "$SRC" -mindepth 1 -maxdepth 1)
if [ "$(echo "$ENTRIES" | wc -l)" -eq 1 ] && [ -d "$ENTRIES" ]; then
  SRC="$ENTRIES"
fi

# Re-seed: wipe any existing (possibly broken/partial) copy, including
# leftover temp folders for this same hash from hung attach attempts.
if [ "$RESEED" = true ]; then
  echo "Removing existing copy of $HASH inside the container..."
  $DOCKER_COMPOSE exec -T -u root frappe sh -c \
    "rm -rf '$TARGET' /home/frappe/.vscode-server/bin/${HASH}_*"
fi

echo "Copying into the frappe container..."
$DOCKER_COMPOSE exec -T -u root frappe mkdir -p "$TARGET"
$DOCKER_COMPOSE cp "$SRC/." "frappe:$TARGET/"
$DOCKER_COMPOSE exec -T -u root frappe chown -R frappe:frappe /home/frappe/.vscode-server

# Sanity check — product.json is what the "already seeded" test keys on.
if ! $DOCKER_COMPOSE exec -T frappe test -f "$TARGET/product.json" 2>/dev/null; then
  echo "Copy finished but $TARGET/product.json is missing — the seed did not"
  echo "land correctly."
  exit 1
fi

[ "$PURGE" = true ] && purge_others

case "$SOURCE" in
  latest)
    echo "Pre-seeded a guessed build ($HASH) since no confirmed VS Code"
    echo "connection has been used. Attach may still work fine — but"
    echo "if it doesn't match your real client, this corrects itself"
    echo "automatically the next time install.sh/startup.sh runs after a real"
    echo "connection." ;;
  *)
    echo "Pre-seed complete for commit $HASH — attach should connect instantly now." ;;
esac