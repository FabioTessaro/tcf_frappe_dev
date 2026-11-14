#!/bin/bash
# Generates the VS Code workspace for this project from what's actually in
# .env / frappe-bench, and installs the extensions the workspace needs.
#
# Writes (all under .vscode/):
#   dev.code-workspace   one folder per installed custom app (TCF_APPS in
#                        .env) + the repo root, the SCSS-compile exclude list
#                        for every vendored app, and the extension
#                        recommendations.
#   settings.json        Python interpreter / Pylance settings.
#   extensions.json      Same extension recommendations, for when the folder
#                        is opened WITHOUT the .code-workspace file.
#
# Existing files are backed up to <file>.bak before being replaced, but only
# when the new content actually differs (so re-running is harmless; the .bak
# is overwritten on every change, so copy it elsewhere if you want to keep it).
#
# Usage:
#   ./bootstrap/setup-workspace.sh                 generate files + install extensions
#   ./bootstrap/setup-workspace.sh --no-install    generate files only
#   ./bootstrap/setup-workspace.sh -h | --help
#
# Safe to re-run any time — e.g. after adding an app to TCF_APPS and running
# bootstrap/setup-bench.sh, so the new app shows up as a workspace folder.
#
# NOTE: this script deliberately does NOT source bootstrap/lib.sh. lib.sh
# probes docker (and may ask for a sudo password) on load, which has nothing
# to do with writing editor config — .env is parsed directly instead, and
# only the handful of keys needed here are read (no secrets are copied into
# any generated file).
#
# NOTE: it also deliberately does NOT create the app folders themselves.
# setup-bench.sh skips `bench get-app` when apps/<name> already exists, so an
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
#   4. Re-run ./bootstrap/setup-workspace.sh.
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
  "wholroyd.jinja"          # Jinja syntax (Frappe web templates)
  "ms-python.python"        # Python
  "mrmlnc.vscode-scss"      # SCSS intellisense
  "glenn2223.live-sass"     # Compiles .scss -> .css on save
  # "publisher.name"        # <- add new extensions above this line
)

# ---------------------------------------------------------------------------
# EXTENSION_SETTINGS — settings that belong to the extensions above, written
# into the "settings" block of dev.code-workspace. Plain JSON, 8-space indent
# is only cosmetic. EVERY entry must end with a trailing comma (the generated
# python-envs setting comes after this block, so the file stays valid).
# Leave it empty if a new extension needs no settings.
# Static settings only: the live-sass exclude list depends on the installed
# apps, so it is generated further down.
# ---------------------------------------------------------------------------
IFS= read -r -d '' EXTENSION_SETTINGS << 'EOF'
        "files.associations": {
            "*.html": "jinja-html"
        },
        "liveSassCompile.settings.generateMap": false,
EOF
EXTENSION_SETTINGS=${EXTENSION_SETTINGS%$'\n'}   # (cosmetic: drop the trailing blank line)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
cd "$(dirname "$0")/.." || exit 1
REPO_ROOT="$(pwd)"
ENV_FILE="$REPO_ROOT/.env"
BENCH_APPS_DIR="$REPO_ROOT/frappe-bench/apps"
APPS_TXT="$REPO_ROOT/frappe-bench/sites/apps.txt"
VSCODE_DIR="$REPO_ROOT/.vscode"
WORKSPACE_FILE="$VSCODE_DIR/dev.code-workspace"
SETTINGS_FILE="$VSCODE_DIR/settings.json"
EXTENSIONS_FILE="$VSCODE_DIR/extensions.json"

usage() {
  cat << EOF
Usage: bootstrap/setup-workspace.sh [options]

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

# write_file TARGET — writes stdin to TARGET, backing up the old file to
# TARGET.bak first if (and only if) the content changed.
write_file() {
  local target="$1" tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [ -f "$target" ]; then
    if cmp -s "$tmp" "$target"; then
      echo "  unchanged: ${target#"$REPO_ROOT"/}"
      rm -f "$tmp"
      return 0
    fi
    cp "$target" "$target.bak"
    echo "  updated:   ${target#"$REPO_ROOT"/} (previous version saved as .bak)"
  else
    echo "  created:   ${target#"$REPO_ROOT"/}"
  fi
  cat "$tmp" > "$target"
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# 1. Work out which apps are installed
# ---------------------------------------------------------------------------

# Custom apps: the actual codebase, listed in TCF_APPS (written by
# setup-env.sh, consumed by setup-bench.sh). These become workspace folders.
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
# the bench's own apps.txt covers anything installed some other way. These are
# excluded from live-sass so it doesn't try to compile their stylesheets.
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
echo "Vendored apps (excluded from live-sass): ${VENDORED_APPS[*]:-none}"

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
    echo "         Re-run this script once setup-bench.sh has fetched it."
  fi
done

# live-sass exclude list: fixed entries + every vendored app.
EXCLUDES_JSON='            "/**/node_modules/**",
            "/**/.vscode/**"'
for app in "${VENDORED_APPS[@]+"${VENDORED_APPS[@]}"}"; do
  EXCLUDES_JSON+=',
            "/**/frappe-bench/apps/'"$app"'/**"'
done
EXCLUDES_JSON+=',
            "/**/frappe-bench/apps/**/node_modules/**"'

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

write_file "$WORKSPACE_FILE" << EOF
{
    "folders": [
$FOLDERS_JSON
    ],
    "extensions": {
        "recommendations": [
$(extensions_json '            ')
        ]
    },
    "settings": {
$EXTENSION_SETTINGS
        "liveSassCompile.settings.excludeList": [
$EXCLUDES_JSON
        ],
        "python-envs.pythonProjects": [
            {
                "path": ".",
                "envManager": "ms-python.python:venv",
                "packageManager": "ms-python.python:pip"
            }
        ]
    }
}
EOF

# Python / Pylance settings. Edit here (not in the generated file) if you
# want to change them — the next run would overwrite manual edits.
write_file "$SETTINGS_FILE" << 'EOF'
{
    "python.defaultInterpreterPath": "./frappe-bench/env/bin/python",
    "python-envs.pythonProjects": [
        {
            "path": ".",
            "envManager": "ms-python.python:venv",
            "packageManager": "ms-python.python:pip"
        }
    ],
    "python.analysis.typeCheckingMode": "basic",
    "python.analysis.diagnosticSeverityOverrides": {
        "reportMissingTypeStubs": "none",
        "reportUnknownArgumentType": "none",
        "reportUnknownLambdaType": "none",
        "reportUnknownMemberType": "none",
        "reportUnknownParameterType": "none",
        "reportUnknownVariableType": "none",
        "reportUntypedBaseClass": "none",
        "reportUntypedClassDecorator": "none",
        "reportUntypedFunctionDecorator": "none",
        "reportMissingParameterType": "none",
        "reportMissingTypeArgument": "none"
    }
}
EOF

write_file "$EXTENSIONS_FILE" << EOF
{
    "recommendations": [
$(extensions_json '        ')
    ]
}
EOF

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