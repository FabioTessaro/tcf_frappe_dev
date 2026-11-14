#!/bin/bash
# Creates a brand-new Frappe app in the bench, installs it on the site, puts it
# in its own git repo on your remote, and registers it in .env and in the
# VS Code workspace. Run it AFTER install.sh has provisioned the bench.
#
# Works from either place — it detects where it is:
#   - inside the frappe container (`bench` is on PATH): runs bench directly
#   - on the host (the VM): runs bench/pre-commit through
#     `docker compose exec frappe`, so the containers must be up (./startup.sh)
# Everything else (git, .env, .vscode) runs where you started the script; the
# repo is bind-mounted into the container, so both sides see the same files.
#   ./new-app.sh tcf_foo
#
# Steps:
#   1. bench new-app <name>          (asks its own questions: title, license, ...)
#   2. bench --site <site> install-app <name>
#   3. asks for the branch name (default: main) and renames the app's branch
#   4. asks you to create an EMPTY repo on the remote, then pushes (plain git
#      only, no GitHub CLI needed)
#   5. appends <name> to the end of TCF_APPS in .env — only if the push succeeded
#   6. adds the app as a folder in .vscode/dev.code-workspace, if that file exists
#   7. pre-commit install
#
# Options:
#   --no-install   skip `bench install-app` (app is created but not installed)
#   --no-push      skip the remote/push step (.env is then NOT updated; .vscode still is)
#   -h, --help     show this help
#
# The remote URL is ${TCF_APPS_GIT_PREFIX}/<name>.git, the same URL
# provision-bench.sh clones from, so the repo name must equal the app name.

set -u

cd "$(dirname "$0")" || exit 1
REPO_ROOT="$(pwd)"
ENV_FILE="$REPO_ROOT/.env"
BENCH_DIR="$REPO_ROOT/frappe-bench"
WORKSPACE_FILE="$REPO_ROOT/.vscode/dev.code-workspace"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

DO_INSTALL=true
DO_PUSH=true
APP=""
for arg in "$@"; do
  case "$arg" in
    --no-install) DO_INSTALL=false ;;
    --no-push) DO_PUSH=false ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $arg"; usage; exit 1 ;;
    *) if [ -z "$APP" ]; then APP="$arg"; else echo "Only one app name allowed."; exit 1; fi ;;
  esac
done

# env_value KEY — container environment first (compose loads .env into it),
# then .env itself. Parsed rather than sourced.
env_value() {
  local val="${!1:-}" line
  if [ -z "$val" ] && [ -f "$ENV_FILE" ]; then
    line=$(grep -E "^[[:space:]]*$1=" "$ENV_FILE" | tail -n 1) || true
    line=${line#*=}; line=${line%$'\r'}
    line=${line#\"}; line=${line%\"}; line=${line#\'}; line=${line%\'}
    val="$line"
  fi
  printf '%s' "$val"
}

die() { echo "Error: $*" >&2; exit 1; }

# --- Where are we? ----------------------------------------------------------
CONTAINER_WORKSPACE="/workspace"            # repo mount point inside the container
CONTAINER_BENCH="$CONTAINER_WORKSPACE/frappe-bench"
IN_CONTAINER=false
command -v bench > /dev/null 2>&1 && IN_CONTAINER=true

[ -f "$ENV_FILE" ] || die "No .env at $ENV_FILE (run ./install.sh first)."
[ -f "$BENCH_DIR/sites/apps.txt" ] \
  || die "frappe-bench isn't provisioned yet. Run ./install.sh (or bootstrap/provision-bench.sh) first."

if [ "$IN_CONTAINER" = true ]; then
  echo "Running inside the container."
else
  # On the host: reuse the project's docker/compose wrapper (handles
  # sudo-or-not detection) and make sure the frappe container is up.
  # shellcheck source=bootstrap/project-common.sh
  source "$REPO_ROOT/bootstrap/project-common.sh"
  case "$DOCKER_STATUS" in
    1) die "Docker isn't installed here, and 'bench' isn't on PATH either. Run ./install.sh first." ;;
    2) die "Docker is installed but its daemon isn't reachable. Run ./startup.sh first." ;;
  esac
  $DOCKER_COMPOSE exec -T frappe true > /dev/null 2>&1 \
    || die "The frappe container isn't running. Run ./startup.sh first."
  echo "Running on the host (bench commands go through docker compose exec)."
fi

# bench_run ARGS... — run `bench ARGS` from the bench directory, wherever we are.
bench_run() {
  if [ "$IN_CONTAINER" = true ]; then
    ( cd "$BENCH_DIR" && bench "$@" )
  else
    $DOCKER_COMPOSE exec -w "$CONTAINER_BENCH" frappe bench "$@"
  fi
}

# precommit_install — pre-commit lives in the container (uv tool install in
# provision-bench.sh), so the hook has to be installed through it.
precommit_install() {
  local cmd='export PATH="$HOME/.local/bin:$PATH"; pre-commit install'
  if [ "$IN_CONTAINER" = true ]; then
    ( cd "$APP_DIR" && bash -c "$cmd" )
  else
    $DOCKER_COMPOSE exec -T -w "$CONTAINER_BENCH/apps/$APP" frappe bash -c "$cmd"
  fi
}

# git_app ARGS... — git against the new app's repo. safe.directory is passed
# per command because on the host the files were created by the container's
# user, and git refuses "dubious ownership" if the UIDs differ.
git_app() {
  git -c safe.directory="$APP_DIR" -C "$APP_DIR" "$@"
}

SITE=$(env_value TCF_SITE_NAME)
[ -n "$SITE" ] || die "TCF_SITE_NAME isn't set in .env."
PREFIX=$(env_value TCF_APPS_GIT_PREFIX)
[ -n "$PREFIX" ] || die "TCF_APPS_GIT_PREFIX isn't set in .env."

# --- App name ---------------------------------------------------------------
if [ -z "$APP" ]; then
  read -r -p "New app name (lowercase, digits, underscores; e.g. tcf_foo): " APP
fi
[[ "$APP" =~ ^[a-z][a-z0-9_]*$ ]] \
  || die "'$APP' isn't a valid app name (must start with a letter; only a-z, 0-9, _)."
[ -e "$BENCH_DIR/apps/$APP" ] && die "frappe-bench/apps/$APP already exists."
for existing in $(env_value TCF_APPS); do
  [ "$existing" = "$APP" ] && die "$APP is already listed in TCF_APPS."
done

REMOTE_URL="${PREFIX}/${APP}.git"
echo "App:     $APP"
echo "Site:    $SITE"
echo "Remote:  $REMOTE_URL"
echo ""

# --- 1. Scaffold ------------------------------------------------------------
# bench asks its own questions (title, description, publisher, license, ...);
# the set differs between Frappe versions, so they're left interactive.
echo "Creating the app (answer bench's prompts)..."
bench_run new-app "$APP" || die "bench new-app failed."
APP_DIR="$BENCH_DIR/apps/$APP"
[ -d "$APP_DIR" ] || die "bench reported success but $APP_DIR doesn't exist."

# bench normally git-inits and makes an initial commit; make sure of it.
if [ ! -e "$APP_DIR/.git" ]; then   # (rev-parse would wrongly find this repo's own .git)
  git_app init -q
fi
if ! git_app rev-parse HEAD > /dev/null 2>&1; then
  git_app add -A
  git_app commit -q -m "feat: initialize app" \
    || die "Couldn't make the initial commit (is git user.name/user.email set?)."
fi

# --- 2. Install on the site -------------------------------------------------
if [ "$DO_INSTALL" = true ]; then
  echo ""
  echo "Installing $APP on $SITE..."
  bench_run --site "$SITE" install-app "$APP" \
    || echo "Warning: install-app failed — fix and run it by hand:
  bench --site $SITE install-app $APP"
fi

# --- 3. Branch name ---------------------------------------------------------
echo ""
BRANCH="main"
if [ -t 0 ]; then
  read -r -p "Branch name [main]: " reply
  BRANCH="${reply:-main}"
fi
git check-ref-format --branch "$BRANCH" > /dev/null 2>&1 \
  || die "'$BRANCH' isn't a valid branch name."
git_app branch -M "$BRANCH" || die "Couldn't rename the branch to '$BRANCH'."
echo "Branch: $BRANCH"

# --- 4. Remote + push -------------------------------------------------------
PUSHED=false
if [ "$DO_PUSH" = true ]; then
  echo ""
  git_app remote remove origin 2> /dev/null || true
  git_app remote add origin "$REMOTE_URL"

  if [ -t 0 ]; then
    echo "Create an EMPTY repo named '$APP' at the remote (no README, .gitignore or"
    case "$PREFIX" in
      *github.com*)
        echo "license) — on GitHub: https://github.com/new  (owner: ${PREFIX##*[:/]}, name: $APP)." ;;
      *)
        echo "license) at: $REMOTE_URL" ;;
    esac
    read -r -p "Press Enter when it exists (or type 's' to skip the push): " reply
    [ "$reply" = "s" ] && DO_PUSH=false
  else
    echo "No TTY — can't wait for you to create the remote repo; skipping the push."
    DO_PUSH=false
  fi

  if [ "$DO_PUSH" = true ]; then
    echo "Pushing branch '$BRANCH'..."
    if git_app push -u origin "$BRANCH"; then
      PUSHED=true
    else
      echo "Push failed. Check the repo exists, is empty, and your SSH key has access, then:"
      echo "  git -C frappe-bench/apps/$APP push -u origin $BRANCH"
    fi
  fi
fi

# --- 5. Append to TCF_APPS in .env (only once the push succeeded) ------------
# A rebuild (provision-bench.sh) clones every app in TCF_APPS from the remote, so
# an app that isn't there yet would break it.
echo ""
if [ "$PUSHED" = true ]; then
  NEW_APPS=$(echo "$(env_value TCF_APPS) $APP" | xargs)
  # Written QUOTED on purpose: an unquoted multi-word value (TCF_APPS=a b c)
  # makes `source .env` (lib.sh's load_env) try to run "b" as a command and
  # abort scripts that use set -e.
  if grep -qE '^[[:space:]]*TCF_APPS=' "$ENV_FILE"; then
    sed -i -E "s|^[[:space:]]*TCF_APPS=.*|TCF_APPS=\"${NEW_APPS}\"|" "$ENV_FILE"
  else
    printf 'TCF_APPS="%s"\n' "$NEW_APPS" >> "$ENV_FILE"
  fi
  echo "Added $APP to the end of TCF_APPS in .env."
else
  echo "Nothing was pushed, so $APP was NOT added to TCF_APPS in .env."
  echo "Push it, then add it to the end of the list by hand:"
  echo "  git -C frappe-bench/apps/$APP push -u origin $BRANCH"
  echo "  TCF_APPS=\"$(env_value TCF_APPS) $APP\""
fi

# --- 6. VS Code workspace (only if it already exists) -----------------------
if [ -f "$WORKSPACE_FILE" ]; then
  if command -v python3 > /dev/null 2>&1; then
    python3 - "$WORKSPACE_FILE" "$APP" << 'PYEOF' \
      || echo "Couldn't edit .vscode/dev.code-workspace automatically (comments or unusual format?) — add this folder by hand:
  { \"path\": \"../frappe-bench/apps/$APP\" }"
import json, sys
path, app = sys.argv[1], sys.argv[2]
text = open(path).read()
data = json.loads(text)
entry = "../frappe-bench/apps/" + app
folders = data.setdefault("folders", [])
if any(f.get("path") == entry for f in folders):
    print("Workspace already lists " + app + ".")
else:
    folders.append({"path": entry})
    # Keep the file's existing indentation style (tabs or spaces).
    indent = "\t" if "\n\t" in text else 4
    with open(path, "w") as fh:
        json.dump(data, fh, indent=indent, ensure_ascii=False)
        fh.write("\n")
    print("Added " + app + " as a folder in .vscode/dev.code-workspace.")
PYEOF
  else
    echo "python3 not found — add this folder to .vscode/dev.code-workspace by hand:"
    echo "  { \"path\": \"../frappe-bench/apps/$APP\" }"
  fi
else
  echo "No .vscode/dev.code-workspace yet — skipped (bootstrap/configure-workspace.sh creates it)."
fi

# --- 7. pre-commit ----------------------------------------------------------
precommit_install > /dev/null 2>&1 \
  && echo "pre-commit hooks installed." \
  || echo "Skipped pre-commit install (pre-commit not available, or no config)."

echo ""
echo "Done: $APP is at frappe-bench/apps/$APP"