#!/bin/bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Generates the VS Code workspace for this project from what's actually in
# .env / frappe-bench, and installs the extensions the workspace needs.
#
# Writes (all under .vscode/):
#   dev.code-workspace   one folder per installed custom app (TCF_APPS in
#                        .env) + the repo root and extension recommendations.
#   settings.json        Python interpreter / Pylance settings.
#   extensions.json      Same extension recommendations, for when the folder
#                        is opened WITHOUT the .code-workspace file.
#
# Existing files are backed up to <file>.bak before being replaced, but only
# when the new content actually differs (so re-running is harmless; the .bak
# is overwritten on every change, so copy it elsewhere if you want to keep it).
#
# Usage:
#   ./bootstrap/configure-workspace.sh                 generate files + install extensions
#   ./bootstrap/configure-workspace.sh --no-install    generate files only
#   ./bootstrap/configure-workspace.sh -h | --help
#
# Safe to re-run any time — e.g. after adding an app to TCF_APPS and running
# bootstrap/provision-bench.sh, so the new app shows up as a workspace folder.
#
# NOTE: this script deliberately does NOT source bootstrap/project-common.sh. That
# helper probes docker (and may ask for a sudo password) on load, which has nothing
# to do with writing editor config — .env is parsed directly instead, and
# only the handful of keys needed here are read (no secrets are copied into
# any generated file).
#
# NOTE: it also deliberately does NOT create the app folders themselves.
# provision-bench.sh skips `bench get-app` when apps/<name> already exists, so an
# empty pre-created folder would stop the app from ever being cloned. Apps
# that aren't on disk yet are skipped with a warning — re-run this script
# after provisioning.
#
# ---------------------------------------------------------------------------
# HOW TO ADD MORE EXTENSIONS LATER (the easy way)
# ---------------------------------------------------------------------------
#   1. Find the extension ID: open the extension's page in VS Code (or the
#      Marketplace) -> "More Info" -> "Identifier". It looks like
#      publisher.name, e.g. "esbenp.prettier-vscode".
#   2. Add it as a new line in the EXTENSIONS array below.
#   3. (Optional) If it needs settings, add them to EXTENSION_SETTINGS below
#      (the fragment is plain JSON; every line/entry must end with a comma).
#   4. Re-run ./bootstrap/configure-workspace.sh.
# That's it: the same list feeds the workspace recommendations, extensions.json
# and the CLI install step — there is nothing else to keep in sync.
# ---------------------------------------------------------------------------

set -u
# Deliberately no "set -e": writing the files is the important part, and the
# extension install is best-effort — a missing/unreachable VS Code CLI must
# never turn into a failed run.

# ---------------------------------------------------------------------------
# EXTENSIONS — one ID per line, in "publisher.name" form.
# ---------------------------------------------------------------------------
EXTENSIONS=(
  "ms-python.python"        # Python
  "ms-python.vscode-pylance" # Python language server
  "Vue.volar"               # Vue 3 language support
  "dbaeumer.vscode-eslint"  # ESLint
  "stylelint.vscode-stylelint" # SCSS/CSS linting
  "bradlc.vscode-tailwindcss" # Tailwind IntelliSense
  "mrmlnc.vscode-scss"      # SCSS IntelliSense
  "wholroyd.jinja"          # Jinja syntax (Frappe web templates)
  "esbenp.prettier-vscode"  # Prettier
  "ms-playwright.playwright" # Playwright test runner
  # "publisher.name"        # <- add new extensions above this line
)

# ---------------------------------------------------------------------------
# EXTENSION_SETTINGS — settings that belong to the extensions above, written
# into the "settings" block of dev.code-workspace. Plain JSON, 8-space indent
# is only cosmetic. EVERY entry must end with a trailing comma (the generated
# python-envs setting comes after this block, so the file stays valid).
# Leave it empty if a new extension needs no settings.
# Static settings only. Sass compilation for the Vue portal is handled by Vite.
# ---------------------------------------------------------------------------
IFS= read -r -d '' EXTENSION_SETTINGS << 'EOF'
        "files.associations": {
            "*.html": "jinja-html"
        },
EOF
EXTENSION_SETTINGS=${EXTENSION_SETTINGS%$'\n'}   # (cosmetic: drop the trailing blank line)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
# shellcheck source=bootstrap/template-lib.sh
source "$SCRIPT_DIR/template-lib.sh"
cd "$REPO_ROOT" || exit 1
ENV_FILE="$REPO_ROOT/.env"
BENCH_APPS_DIR="$REPO_ROOT/frappe-bench/apps"
APPS_TXT="$REPO_ROOT/frappe-bench/sites/apps.txt"
VSCODE_DIR="$REPO_ROOT/.vscode"
WORKSPACE_FILE="$VSCODE_DIR/dev.code-workspace"
SETTINGS_FILE="$VSCODE_DIR/settings.json"
EXTENSIONS_FILE="$VSCODE_DIR/extensions.json"

usage() {
  cat << EOF
Usage: bootstrap/configure-workspace.sh [options]

  --no-install   Only write the .vscode files; don't install extensions
  -h, --help     Show this help
EOF
}

INSTALL_EXTENSIONS=true
for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL_EXTENSIONS=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  echo "No .env file found at $ENV_FILE."
  echo "Run ./install.sh first — it creates .env as part of first-time setup."
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# env_value KEY — prints the value of KEY from .env (last assignment wins),
# with surrounding quotes and CR characters removed. Parsed, not sourced, so
# odd characters in secrets can't break or execute anything.
env_value() {
  local line
  line=$(grep -E "^[[:space:]]*$1=" "$ENV_FILE" | tail -n 1) || true
  line=${line#*=}
  line=${line%$'\r'}
  line=${line#\"}; line=${line%\"}
  line=${line#\'}; line=${line%\'}
  printf '%s' "$line"
}

# contains NEEDLE ITEM... — success if NEEDLE is one of the ITEMs.
contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# Only plain app names are allowed into the generated JSON.
valid_app_name() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

# ---------------------------------------------------------------------------
# 1. Work out which apps are installed
# ---------------------------------------------------------------------------

# Custom apps: the actual codebase, listed in TCF_APPS (written by
# bootstrap/setup-env.sh, consumed by provision-bench.sh). These become workspace folders.
CUSTOM_APPS=()
for app in $(env_value TCF_APPS); do
  if valid_app_name "$app"; then
    contains "$app" "${CUSTOM_APPS[@]+"${CUSTOM_APPS[@]}"}" || CUSTOM_APPS+=("$app")
  else
    echo "Ignoring TCF_APPS entry with unexpected characters: '$app'"
  fi
done

# Vendored apps: upstream code we only read. Every <APP>_VERSION key in .env
# names one (FRAPPE_VERSION -> frappe, ERPNEXT_VERSION -> erpnext, ...), and
# the bench's own apps.txt covers anything installed some other way. This list
# is retained for reporting; Vite owns the portal's Sass compilation.
VENDORED_APPS=()
for app in $(grep -oE '^[[:space:]]*[A-Z0-9_]+_VERSION=' "$ENV_FILE" \
              | sed -E 's/^[[:space:]]*//; s/_VERSION=$//' | tr 'A-Z' 'a-z'); do
  valid_app_name "$app" || continue
  contains "$app" "${CUSTOM_APPS[@]+"${CUSTOM_APPS[@]}"}" && continue
  contains "$app" "${VENDORED_APPS[@]+"${VENDORED_APPS[@]}"}" || VENDORED_APPS+=("$app")
done
if [ -f "$APPS_TXT" ]; then
  while IFS= read -r app || [ -n "$app" ]; do
    app=${app%$'\r'}
    [ -z "$app" ] && continue
    valid_app_name "$app" || continue
    contains "$app" "${CUSTOM_APPS[@]+"${CUSTOM_APPS[@]}"}" && continue
    contains "$app" "${VENDORED_APPS[@]+"${VENDORED_APPS[@]}"}" || VENDORED_APPS+=("$app")
  done < "$APPS_TXT"
fi

echo "Custom apps (TCF_APPS): ${CUSTOM_APPS[*]:-none}"
echo "Vendored apps (upstream dependencies): ${VENDORED_APPS[*]:-none}"

# ---------------------------------------------------------------------------
# 2. Build the dynamic JSON fragments
# ---------------------------------------------------------------------------

# Workspace folders: repo root first, then one per custom app that exists.
FOLDERS_JSON='        {
            "path": ".."
        }'
LISTED_APPS=()
for app in "${CUSTOM_APPS[@]+"${CUSTOM_APPS[@]}"}"; do
  if [ -d "$BENCH_APPS_DIR/$app" ]; then
    FOLDERS_JSON+=',
        {
            "path": "../frappe-bench/apps/'"$app"'"
        }'
    LISTED_APPS+=("$app")
  else
    echo "Warning: frappe-bench/apps/$app doesn't exist yet — not added as a folder."
    echo "         Re-run this script once provision-bench.sh has fetched it."
  fi
done

# Extension IDs as JSON array items (indent passed in, so the same list can
# be reused at different nesting levels).
extensions_json() {
  local indent="$1" ext out="" sep=""
  for ext in "${EXTENSIONS[@]}"; do
    out+="${sep}${indent}\"${ext}\""
    sep=$',\n'
  done
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# 3. Write the files
# ---------------------------------------------------------------------------
mkdir -p "$VSCODE_DIR"
echo ""
echo "Writing VS Code files..."

EXTENSIONS_JSON_INDENT12="$(extensions_json '            ')"
EXTENSIONS_JSON_INDENT8="$(extensions_json '        ')"

render_template "$TEMPLATE_DIR/vscode-workspace.json.template" "$WORKSPACE_FILE" \
  "FOLDERS_JSON=$FOLDERS_JSON" \
  "EXTENSIONS_JSON_INDENT12=$EXTENSIONS_JSON_INDENT12" \
  "EXTENSION_SETTINGS=$EXTENSION_SETTINGS" || exit 1

render_template "$TEMPLATE_DIR/vscode-settings.json.template" "$SETTINGS_FILE" || exit 1
render_template "$TEMPLATE_DIR/vscode-extensions.json.template" "$EXTENSIONS_FILE" \
  "EXTENSIONS_JSON_INDENT8=$EXTENSIONS_JSON_INDENT8" || exit 1

# ---------------------------------------------------------------------------
# 4. Install the extensions on THIS machine (best effort)
# ---------------------------------------------------------------------------
# "This machine" is wherever the script runs: run it on the VM for the
# Remote-SSH side, and inside the frappe container (it's mounted at
# /workspace) for the "Attach to Running Container" side. VS Code installs
# extensions per-machine, so each side needs its own copy. Machines this
# script can't reach (e.g. your laptop's UI-side extensions) are covered by
# the recommendations written above: VS Code offers to install them the first
# time the workspace is opened there.

# find_vscode_cli — prints the path of a VS Code CLI able to install
# extensions here, or nothing. Tries, in order:
#   1. `code` on PATH (desktop install, or a VS Code integrated terminal)
#   2. the headless server CLI that Remote-SSH / Attach leave under
#      ~/.vscode-server (newest build wins)
find_vscode_cli() {
  local candidate
  if command -v code > /dev/null 2>&1; then
    command -v code
    return 0
  fi
  for candidate in \
    "$(ls -td "$HOME"/.vscode-server/cli/servers/Stable-*/server/bin/code-server 2>/dev/null | head -n 1)" \
    "$(ls -td "$HOME"/.vscode-server/bin/*/bin/code-server 2>/dev/null | head -n 1)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

INSTALL_FAILED=()
if [ "$INSTALL_EXTENSIONS" = true ]; then
  echo ""
  echo "Installing extensions..."
  CODE_CLI=$(find_vscode_cli) || CODE_CLI=""
  if [ -z "$CODE_CLI" ]; then
    echo "  No VS Code CLI found on this machine (no 'code' on PATH and no"
    echo "  ~/.vscode-server yet) — skipping the install step. The workspace"
    echo "  still recommends the extensions, so VS Code will offer to install"
    echo "  them when you open it. Connect once with VS Code and re-run this"
    echo "  script to install them from the command line instead."
  else
    echo "  Using: $CODE_CLI"
    INSTALLED=$("$CODE_CLI" --list-extensions 2>/dev/null | tr 'A-Z' 'a-z') || INSTALLED=""
    for ext in "${EXTENSIONS[@]}"; do
      if printf '%s\n' "$INSTALLED" | grep -qxF "$(printf '%s' "$ext" | tr 'A-Z' 'a-z')"; then
        echo "  already installed: $ext"
      elif "$CODE_CLI" --install-extension "$ext" > /dev/null 2>&1; then
        echo "  installed:         $ext"
      else
        echo "  FAILED:            $ext"
        INSTALL_FAILED+=("$ext")
      fi
    done
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Workspace ready: ${WORKSPACE_FILE#"$REPO_ROOT"/}"
echo "  Folders:    repo root + ${LISTED_APPS[*]:-no apps found on disk yet}"
if [ "${#INSTALL_FAILED[@]}" -gt 0 ]; then
  echo "  Could not install: ${INSTALL_FAILED[*]}"
  echo "  (check internet access, or install them from the Extensions view —"
  echo "   they're listed under \"Workspace Recommendations\")"
fi
echo "Open it with: File > Open Workspace from File... > .vscode/dev.code-workspace"