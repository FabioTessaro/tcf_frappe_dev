#!/usr/bin/env bash
# new-app.sh — create an empty app repository that follows the guide, or check
# one out, and add it to the development environment (guide 500, playbook
# 80-playbooks/new-feature-app.md). Runs on the host or inside the frappe
# container.
#
# Usage: ./new-app.sh [options]
#
#   kinds              core (the portal shell and the sdks; exactly one, first),
#                      foundation (shared business primitives, no frontend),
#                      feature (business features with a portal frontend)
#   app on GitHub      cloned into frappe-bench/apps/<app>
#   app not on GitHub  scaffolded from bootstrap/templates/app (shared
#                      configuration from the platform commit on origin/main,
#                      lockfiles resolved now), the GitHub repository created,
#                      pushed, and the repository settings the plan allows applied
# Then, in every case: the app is added to CUSTOM_APPS in .env (and CORE_APP
# for the core app), fetched into the bench, installed on the main site and the
# full test site (the core app also on the minimal test site), the portal is
# rebuilt, and the VS Code workspace updated. Last, it checks whether CI needs
# the APPS_READ_TOKEN secret (a private platform, dependency or app) and, if a
# repository lacks it, says exactly how to create and add it (by hand).
#
# Options:
#   --answers FILE   take answers from FILE (KEY=VALUE): APP_NAME, APP_KIND
#                    (core|foundation|feature), APP_TITLE, APP_DESCRIPTION,
#                    APP_REQUIRED (other hard dependencies besides the core
#                    app, space separated), APP_VISIBILITY (private|public),
#                    APP_LICENSE (proprietary|mit|apache-2.0|agpl-3.0|gpl-3.0),
#                    APP_COPYRIGHT, APP_TEAM (solo|team).
#                    See bootstrap/templates/new-app.answers.example.conf
#   --no-push        scaffold and commit only, into --dir: no GitHub calls, no
#                    changes to .env or the bench (tests)
#   --dir DIR        scaffold folder for --no-push (default: .state/new-app/<app>)
#   -y, --yes        don't ask for the final confirmation
#   --trace          also write a bash execution trace into the log
#   -h, --help       show this help
#
# Needs: git, python3, gh logged in (host: ./install.sh, git component; the
# container: logged in with the host's token by ./initialize.sh), the platform
# repository in ./platform (./new-platform.sh), a running development
# environment (node, yarn, uv and bench run in the frappe container).
# Log: logs/new-app-<timestamp>.log
set -o pipefail
# shellcheck source=bootstrap/lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/apps.sh
source "$LIB_DIR/apps.sh"
# shellcheck source=bootstrap/lib/project.sh
source "$LIB_DIR/project.sh"
# shellcheck source=bootstrap/lib/scaffold.sh
source "$LIB_DIR/scaffold.sh"

ANSWERS_FILE=""; NO_PUSH=false; ASSUME_YES=false; SCAFFOLD_DIR=""
for a in "$@"; do [[ "$a" == -h || "$a" == --help ]] && { usage_from_header "$0"; exit 0; }; done
script_init new-app "$@"
set -- "${SCRIPT_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --answers) ANSWERS_FILE="${2:-}"; shift ;;
    --answers=*) ANSWERS_FILE="${1#*=}" ;;
    --dir) SCAFFOLD_DIR="${2:-}"; shift ;;
    --dir=*) SCAFFOLD_DIR="${1#*=}" ;;
    --no-push) NO_PUSH=true ;;
    -y|--yes) ASSUME_YES=true ;;
    *) ui_die "Unknown option: $1" "See ./new-app.sh --help" ;;
  esac
  shift
done
[[ -z "$SCAFFOLD_DIR" || "$SCAFFOLD_DIR" == /* ]] || SCAFFOLD_DIR="$REPO_ROOT/$SCAFFOLD_DIR"
[[ -z "$SCAFFOLD_DIR" || "$NO_PUSH" == true ]] || ui_die "--dir is for --no-push only."

declare -A ANS=() CUR=()
if [[ -n "$ANSWERS_FILE" ]]; then
  [[ -f "$ANSWERS_FILE" ]] || ui_die "Answers file not found: $ANSWERS_FILE"
  env_parse "$ANSWERS_FILE" ANS
fi
[[ -f "$ENV_FILE" ]] || ui_die "No .env yet." "Run ./setup.sh and ./initialize.sh first."
env_parse "$ENV_FILE" CUR
has_answer() { [[ -n "${ANS[$1]+x}" ]]; }
need_tty_for() {
  [[ "$UI_TTY_IN" == true ]] && return 0
  ui_die "No terminal to ask for $2 ($1)." "Add $1=… to the answers file (--answers)."
}
# Frappe module names an app must not take (SYS-APP-001), and the apps of the catalog.
RESERVED=(frappe core desk website email integrations automation printing contacts geo social utils custom)
catalog_load
valid_new_app_name() {
  valid_app_name "$1" || return 1
  contains "$1" "${RESERVED[@]}" "${CAT_NAMES[@]}" && return 1
  return 0
}
WHERE="host"; in_dev_container && WHERE="frappe container"

ui_banner "New app" "an empty app that follows the guide, in frappe-bench/apps (running on the $WHERE)"

# =============================================================================
ui_section "Prerequisites"
for t in git python3; do command -v "$t" >/dev/null 2>&1 || ui_die "$t is not installed." "Run ./install.sh."; done
if ! in_dev_container; then
  docker_require
  frappe_running || ui_die "The frappe container is not running." "Run ./initialize.sh."
fi
ui_run --quiet-fail "Checking node, yarn, uv and bench in the frappe container" -- \
  dev_run "$REPO_ROOT" bash -c 'command -v node && command -v yarn && command -v uv && command -v bench' \
  || ui_die "node, yarn, uv or bench is missing in the frappe container." "Run ./initialize.sh."
ui_ok "Development tools are available in the frappe container"
if [[ "$NO_PUSH" == false ]]; then
  command -v gh >/dev/null 2>&1 || ui_die "gh (GitHub CLI) is not installed here." \
    "$(in_dev_container && echo "Run ./initialize.sh on the host (installs it in the container)" || echo "Run ./install.sh --components base,git")"
  ui_run --quiet-fail "Checking the GitHub CLI login" -- gh_logged_in || ui_die "gh is not logged in to GitHub." \
    "$(in_dev_container && echo "Run ./initialize.sh on the host: it logs the container in with the host's token" || echo "Run ./install.sh --components git (or: gh auth login --git-protocol ssh --web)")"
  ui_ok "gh is logged in as $(gh api user --jq .login)"
else
  ui_note "--no-push: nothing is created or read on GitHub, .env and the bench are left alone."
fi

# The platform repository: shared configuration, CI workflow, tool versions.
PLATFORM_DIR="$REPO_ROOT/platform"
[[ -d "$PLATFORM_DIR/.git" ]] || ui_die "No platform repository in ./platform." "Run ./new-platform.sh first."
[[ "$NO_PUSH" == true ]] || ui_run --quiet-fail "Fetching the platform repository" -- git -C "$PLATFORM_DIR" fetch -q origin \
  || ui_warn "Couldn't fetch the platform repository: using the origin/main it had."
PLATFORM_REF=$(git -C "$PLATFORM_DIR" rev-parse -q --verify origin/main 2>/dev/null || git -C "$PLATFORM_DIR" rev-parse HEAD)
PLATFORM_ORIGIN=$(git -C "$PLATFORM_DIR" remote get-url origin 2>/dev/null || true)
[[ "$PLATFORM_ORIGIN" =~ github\.com[:/]([^/]+)/([^/]+)$ ]] || ui_die "./platform has no GitHub origin ('$PLATFORM_ORIGIN')."
PLATFORM_OWNER="${BASH_REMATCH[1]}"; PLATFORM_REPO="${BASH_REMATCH[2]%.git}"
ui_kv "Platform" "$PLATFORM_OWNER/$PLATFORM_REPO at ${PLATFORM_REF:0:12} (origin/main)"
pdocker=$(git -C "$PLATFORM_DIR" show "$PLATFORM_REF:ci-image/Dockerfile" 2>/dev/null) || ui_die "No ci-image/Dockerfile at $PLATFORM_REF in ./platform."
MYPY_VERSION=$(sed -n 's/^ARG MYPY_VERSION=//p' <<<"$pdocker"); IMPORT_LINTER_VERSION=$(sed -n 's/^ARG IMPORT_LINTER_VERSION=//p' <<<"$pdocker")
[[ -n "$MYPY_VERSION" && -n "$IMPORT_LINTER_VERSION" ]] || ui_die "The CI image of the platform does not pin mypy and import-linter."

# =============================================================================
ui_section "App"
CORE="${CUR[CORE_APP]:-}"
if has_answer APP_NAME; then APP="${ANS[APP_NAME]}"
else
  need_tty_for APP_NAME "the app name"
  ui_input --validate valid_new_app_name --error "lowercase letters, digits and '_', starting with a letter; not a Frappe module or a catalog app" \
    "App name (the Frappe app and the repository)"
  APP="$UI_VALUE"
fi
valid_new_app_name "$APP" || ui_die "Invalid app name '$APP' (SYS-APP-001: ^[a-z][a-z0-9_]*\$, not a Frappe module, not a catalog app)."
if [[ -n "$CORE" && "$APP" == "$CORE" ]]; then KIND=core
elif has_answer APP_KIND; then KIND="${ANS[APP_KIND]}"
elif [[ -z "$CORE" ]]; then
  KIND=core; ui_note "There is no core app yet: $APP is the core app."
else
  need_tty_for APP_KIND "the app kind"
  ui_select "Kind of $APP (guide 11)" \
    "feature::Feature app::business features with a portal frontend" \
    "foundation::Foundation app::business primitives shared by feature apps, no frontend" || exit 1
  KIND="$UI_VALUE"
fi
case "$KIND" in
  core) [[ -z "$CORE" || "$CORE" == "$APP" ]] || ui_die "$CORE is already the core app: there is exactly one." ;;
  feature|foundation) [[ -n "$CORE" ]] || ui_die "There is no core app yet." "Create it first: ./new-app.sh (APP_KIND=core)." ;;
  *) ui_die "APP_KIND must be core, foundation or feature (got '$KIND')." ;;
esac
[[ "$KIND" == core ]] && CORE="$APP"
OWNER=$(owner_from_prefix "${CUR[CUSTOM_APPS_GIT_PREFIX]:-}" || true)
[[ -n "$OWNER" ]] || ui_die "CUSTOM_APPS_GIT_PREFIX in .env is not a GitHub prefix." "Run ./setup.sh (custom apps)."
[[ "$OWNER" == "$PLATFORM_OWNER" ]] || ui_warn "Apps go to $OWNER, the platform is under $PLATFORM_OWNER: the CI workflow and Renovate preset must be readable from $OWNER."
SLUG="$OWNER/$APP"; URL=$(cfg_custom_url CUR "$APP")
ui_kv "App" "$APP ($KIND)"; ui_kv "Repository" "$SLUG ($URL)"

# --- current state: converges from any of them -------------------------------------
#   local   none | present (frappe-bench/apps/<app>)
#   GitHub  missing | empty | populated | skipped (--no-push)
APP_DIR="$BENCH_DIR/apps/$APP"; LOCAL=none; REMOTE=skipped
if [[ -e "$APP_DIR" ]]; then
  origin=$(git -C "$APP_DIR" remote get-url origin 2>/dev/null || true)
  [[ "$origin" == "$URL" || "$origin" == "https://github.com/$SLUG"* || "$origin" == "git@github.com:$SLUG.git" ]] \
    || ui_die "frappe-bench/apps/$APP exists but is not a checkout of $SLUG (origin: '${origin:-none}')."
  LOCAL=present
fi
if [[ "$NO_PUSH" == false ]]; then
  if ui_run --quiet-fail "Looking for $SLUG on GitHub" -- gh_repo_exists "$SLUG"; then
    if gh api "repos/$SLUG/branches/main" --silent >/dev/null 2>&1; then REMOTE=populated; else REMOTE=empty; fi
  else
    REMOTE=missing
  fi
fi
[[ "$LOCAL" == present && "$REMOTE" != populated && "$NO_PUSH" == false ]] && ui_die \
  "frappe-bench/apps/$APP exists but $SLUG has nothing on GitHub." "Push it by hand, or move it away and run again."
SCAFFOLD=false
[[ "$LOCAL" == none && "$REMOTE" != populated ]] && SCAFFOLD=true
case "$LOCAL:$REMOTE" in
  present:*) ui_kv "State" "already in the bench" ;;
  none:populated) ui_kv "State" "on GitHub — will be fetched into the bench" ;;
  none:skipped) ui_kv "State" "will be scaffolded (--no-push)" ;;
  *) ui_kv "State" "will be scaffolded and pushed to $SLUG ($REMOTE on GitHub)" ;;
esac

# =============================================================================
if [[ "$SCAFFOLD" == true ]]; then
  ui_section "Choices"
  def_title="$(sed -E 's/(^|_)([a-z])/\1\U\2/g; s/_/ /g' <<<"$APP")"
  if has_answer APP_TITLE; then TITLE="${ANS[APP_TITLE]}"
  else need_tty_for APP_TITLE "the title"; ui_input --default "$def_title" --validate valid_env_value "Title (shown in Desk)"; TITLE="$UI_VALUE"; fi
  if has_answer APP_DESCRIPTION; then DESCRIPTION="${ANS[APP_DESCRIPTION]}"
  else need_tty_for APP_DESCRIPTION "the description"; ui_input --default "$TITLE" --validate valid_env_value "One-line description"; DESCRIPTION="$UI_VALUE"; fi
  [[ "$TITLE$DESCRIPTION" != *'"'* && "$TITLE$DESCRIPTION" != *'\'* ]] || ui_die "Title and description may not contain \" or \\."

  REQUIRED=()
  if [[ "$KIND" != core ]]; then
    others=(); for a in ${CUR[CUSTOM_APPS]:-}; do [[ "$a" != "$CORE" ]] && others+=("$a"); done
    if has_answer APP_REQUIRED; then read -r -a REQUIRED <<<"${ANS[APP_REQUIRED]}"
    elif (( ${#others[@]} )); then
      need_tty_for APP_REQUIRED "the hard dependencies"
      ui_input --allow-empty "Other hard dependencies besides $CORE (space separated, from: ${others[*]}; prefer none, SYS-DEP-010)"
      read -r -a REQUIRED <<<"$UI_VALUE"
    fi
    for r in "${REQUIRED[@]}"; do
      contains "$r" "${others[@]}" || ui_die "APP_REQUIRED: '$r' is not a custom app of this environment (${others[*]:-none})."
    done
  fi

  if [[ "$REMOTE" == missing ]]; then
    if has_answer APP_VISIBILITY; then VISIBILITY="${ANS[APP_VISIBILITY]}"
    else need_tty_for APP_VISIBILITY "the visibility"; ui_select "Visibility of $SLUG" "private::Private" "public::Public::anyone can read it" || exit 1; VISIBILITY="$UI_VALUE"; fi
    [[ "$VISIBILITY" == private || "$VISIBILITY" == public ]] || ui_die "APP_VISIBILITY must be private or public."
  fi
  if has_answer APP_LICENSE; then LICENSE_KEY="${ANS[APP_LICENSE]}"
  else need_tty_for APP_LICENSE "the licence"; ui_select "Licence of $APP" "${LICENSE_CHOICES[@]}" || exit 1; LICENSE_KEY="$UI_VALUE"; fi
  [[ -n "$(license_name "$LICENSE_KEY")" ]] || ui_die "Unknown licence '$LICENSE_KEY'."
  if [[ "$NO_PUSH" == true && "$LICENSE_KEY" != proprietary ]] && ! command -v gh >/dev/null 2>&1; then
    ui_warn "--no-push without gh: LICENSE written as proprietary placeholder."; LICENSE_KEY=proprietary
  fi
  if has_answer APP_COPYRIGHT; then HOLDER="${ANS[APP_COPYRIGHT]}"
  else need_tty_for APP_COPYRIGHT "the copyright holder"; ui_input --default "$(git config --global user.name 2>/dev/null)" --validate valid_env_value "Copyright holder"; HOLDER="$UI_VALUE"; fi
  [[ "$HOLDER" != *'"'* && "$HOLDER" != *'\'* ]] || ui_die "The copyright holder may not contain \" or \\."

  # The core sdk version: provided by the core app, a range for the others (SYS-DEP-002).
  CORE_SDK_VERSION=0.1.0; CORE_SDK_RANGE=""
  if [[ "$KIND" != core ]]; then
    hooks="$BENCH_DIR/apps/$CORE/$CORE/hooks.py"
    [[ -f "$hooks" ]] || ui_die "The core app $CORE is not in frappe-bench/apps." "Run ./initialize.sh."
    sdk=$(python3 -c 'import ast, sys
for n in ast.parse(open(sys.argv[1]).read()).body:
    t = n.targets[0] if isinstance(n, ast.Assign) else getattr(n, "target", None)
    if getattr(t, "id", "") == "core_sdk_version": print(ast.literal_eval(n.value))' "$hooks")
    [[ "$sdk" =~ ^([0-9]+)\.([0-9]+) ]] || ui_die "core_sdk_version of $CORE is not X.Y.Z ('$sdk')."
    major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}"
    # Before 1.0 a minor version may break (semantic versioning).
    if (( major == 0 )); then CORE_SDK_RANGE=">=0.$minor,<0.$((minor + 1))"; else CORE_SDK_RANGE=">=$major.$minor,<$((major + 1)).0"; fi
  fi

  # The empty .pot is what `bench generate-pot-file` writes (Babel of the bench).
  BABEL_VERSION=$(dev_run "$BENCH_DIR" env/bin/python -c 'import babel; print(babel.__version__)' 2>/dev/null) \
    || ui_die "Couldn't read the Babel version of the bench (frappe-bench/env)."

  [[ -n "${VISIBILITY:-}" ]] && ui_kv "Visibility" "$VISIBILITY"
  ui_kv "Title" "$TITLE — $DESCRIPTION"
  ui_kv "Licence" "$(license_name "$LICENSE_KEY") — $HOLDER"
  if [[ "$KIND" == core ]]; then ui_kv "Core sdk" "$CORE_SDK_VERSION (provided)"
  else ui_kv "Requires" "$CORE ${REQUIRED[*]} · core sdk $CORE_SDK_RANGE"; fi
  ui_kv "Guide" "$(guide_version)"
  if [[ "$ASSUME_YES" == false && "$UI_TTY_IN" == true ]]; then
    msg="Create $SLUG"; [[ "$NO_PUSH" == true ]] && msg="Scaffold $APP locally (no push)"
    ui_confirm "$msg?" y || { ui_info "Nothing done."; exit 0; }
  fi

  # ===========================================================================
  ui_section "Scaffold"
  DIR="${SCAFFOLD_DIR:-$STATE_DIR/new-app/$APP}"
  [[ "$DIR" == "$REPO_ROOT"/* ]] || ui_die "The scaffold folder must be inside the repository (the frappe container sees it there): $DIR"
  if [[ -e "$DIR" ]]; then
    [[ -n "$SCAFFOLD_DIR" && -n "$(ls -A "$DIR" 2>/dev/null)" ]] && ui_die "$DIR is not empty."
    rm -rf "$DIR"
  fi
  mkdir -p "$DIR"
  py_required="[\"$CORE\""; for r in "${REQUIRED[@]}"; do py_required+=", \"$r\""; done; py_required+="]"
  vals=(
    # The module "<App> Shared" must scrub to the folder <app>_shared (BE-STR-004).
    "APP=$APP" "APP_TITLE=$TITLE" "APP_MODULE=$(sed -E 's/(^|_)([a-z])/\1\U\2/g; s/_/ /g' <<<"$APP")" "APP_KIND=$KIND" "APP_ROUTE=${APP//_/-}" "APP_DESCRIPTION=$DESCRIPTION"
    "OWNER=$OWNER" "PLATFORM_REPO=$PLATFORM_REPO" "PLATFORM_REF=$PLATFORM_REF" "CORE_APP=$CORE"
    "CORE_SDK_VERSION=$CORE_SDK_VERSION" "CORE_SDK_RANGE=$CORE_SDK_RANGE"
    "REQUIRED_APPS_PY=$py_required" "REQUIRED_APPS_LIST=${REQUIRED[*]}"
    "PUBLISHER=$HOLDER" "LICENSE_NAME=$(license_name "$LICENSE_KEY")" "LICENSE_SPDX=$(license_spdx "$LICENSE_KEY")"
    "GUIDE_VERSION=$(guide_version)" "TODAY=$(date +%F)"
    "MYPY_VERSION=$MYPY_VERSION" "IMPORT_LINTER_VERSION=$IMPORT_LINTER_VERSION"
    "YEAR=$(date +%Y)" "POT_DATE=$(date -u '+%Y-%m-%d %H:%M+0000')" "BABEL_VERSION=$BABEL_VERSION"
    "IS_CORE=$([[ $KIND == core ]] && echo true || echo false)"
    "IS_FEATURE=$([[ $KIND == feature ]] && echo true || echo false)"
    "IS_FOUNDATION=$([[ $KIND == foundation ]] && echo true || echo false)"
  )
  LAYERS=(common); if [[ "$KIND" == core ]]; then LAYERS+=(core); else LAYERS+=(app); fi
  [[ "$KIND" == feature ]] && LAYERS+=(feature)
  _scaffold() {
    local l
    for l in "${LAYERS[@]}"; do scaffold_render_tree "$TEMPLATE_DIR/app/$l" "$DIR" "${vals[@]}" || return 1; done
    # The shared configuration of the pinned platform commit (DEL-TOOL-003).
    git -C "$PLATFORM_DIR" show "$PLATFORM_REF:shared-config/files.txt" \
      | awk -v core="$([[ $KIND == core ]] && echo 1 || echo 0)" '!/^#/ && NF == 3 && ($3 == "all" || (core && $3 == "core")) {print $1, $2}' \
      | while read -r s d; do
          mkdir -p "$DIR/$(dirname "$d")" && git -C "$PLATFORM_DIR" show "$PLATFORM_REF:shared-config/$s" > "$DIR/$d" || exit 1
        done
  }
  ui_run "Rendering bootstrap/templates/app (${LAYERS[*]})" -- _scaffold || ui_die "Scaffolding failed."
  ui_run "Writing the licence ($(license_name "$LICENSE_KEY"))" -- \
    license_write "$LICENSE_KEY" "$HOLDER" "$(date +%Y)" "$DIR/LICENSE" || ui_die "Writing LICENSE failed."

  # Lockfiles, resolved now in the frappe container (DEL-REPO-004).
  ui_run "Resolving the Python lockfile (uv.lock)" -- dev_run "$DIR" uv lock --quiet || ui_die "uv lock failed."
  if [[ "$KIND" == core ]]; then
    _yarn_locks() {
      # Direct dependencies pinned to the versions resolved today; Renovate keeps
      # them current. The first install resolves the ranges, the second records
      # the pins in yarn.lock.
      dev_run "$DIR/frontend" yarn install --non-interactive --silent || return 1
      dev_run "$DIR/frontend" node -e '
        const fs = require("fs");
        const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
        for (const field of ["dependencies", "devDependencies"])
          for (const name of Object.keys(pkg[field] ?? {}))
            pkg[field][name] = JSON.parse(fs.readFileSync(`node_modules/${name}/package.json`, "utf8")).version;
        fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");' || return 1
      dev_run "$DIR/frontend" yarn install --non-interactive --silent || return 1
      dev_run "$DIR/frontend" node scripts/portal.ts generate
    }
    ui_run "Resolving the frontend toolchain (yarn.lock; a minute or two)" -- _yarn_locks || ui_die "yarn install failed (see the log)."
  fi
  _commit() {
    cd "$DIR" && git init -q -b main && git add -A \
      && git -c commit.gpgsign=false commit -q --no-verify -m "chore: scaffold $APP (guide $(guide_version))"
  }
  ui_run "Creating the first commit" -- _commit || ui_die "git commit failed."
  ui_ok "Scaffolded $(git -C "$DIR" ls-files | wc -l) files in ${DIR#"$REPO_ROOT"/}"

  if [[ "$NO_PUSH" == true ]]; then
    ui_info "--no-push: the scaffold stays in ${DIR#"$REPO_ROOT"/} (node_modules included, for checks)."
    exit 0
  fi
  rm -rf "$DIR/node_modules" "$DIR/frontend/node_modules" "$DIR/frontend/.cache"

  # ===========================================================================
  ui_section "GitHub"
  if [[ "$REMOTE" == missing ]]; then
    ui_run "Creating $SLUG ($VISIBILITY)" -- gh repo create "$SLUG" "--$VISIBILITY" --description "$DESCRIPTION" \
      || ui_die "gh repo create failed."
  fi
  git -C "$DIR" remote add origin "$URL"
  ui_run "Pushing main" -- git -C "$DIR" push -q -u origin main \
    || ui_die "git push failed." "Check that $URL accepts your SSH key, then run ./new-app.sh again."
  REMOTE=populated
  TEAM_KEY=APP_TEAM; ask_team_mode ""
  approvals=0; [[ "$TEAM_MODE" == team ]] && approvals=1
  # The required check: job "level1" of the platform workflow, called by job "ci".
  GH_ENVIRONMENTS=false gh_apply_repo_settings "$SLUG" "$approvals" "ci / level1"
fi

if [[ "$NO_PUSH" == true ]]; then ui_info "--no-push: $APP exists already; nothing done."; exit 0; fi

# =============================================================================
ui_section "Development environment"
apps=(); for a in ${CUR[CUSTOM_APPS]:-}; do apps+=("$a"); done
if ! contains "$APP" "${apps[@]}"; then
  # The core app first: it is installed before the apps that require it.
  if [[ "$KIND" == core ]]; then apps=("$APP" "${apps[@]}"); else apps+=("$APP"); fi
  env_set_key CUSTOM_APPS "${apps[*]}" || ui_die "Couldn't write CUSTOM_APPS to .env."
fi
[[ "$KIND" == core ]] && { env_set_key CORE_APP "$APP" || ui_die "Couldn't write CORE_APP to .env."; }
ui_ok "CUSTOM_APPS: ${apps[*]}$([[ $KIND == core ]] && echo " (core: $APP)")"
ui_run "Fetching $APP into the bench" -- provision get-app "$APP" "$URL" "" custom \
  || ui_die "Couldn't fetch $APP into frappe-bench/apps." "See the log, then run ./new-app.sh again."
rm -rf "$STATE_DIR/new-app/$APP"
sites=("${CUR[SITE_NAME]}" "${CUR[TEST_SITE_NAME]}")
[[ "$KIND" == core ]] && sites+=("${CUR[TEST_MINIMAL_SITE_NAME]:-test-minimal.${CUR[SITE_NAME]}}")
for s in "${sites[@]}"; do
  [[ -n "$s" ]] || continue
  ui_run "Installing $APP on $s" -- provision site-install "$s" "$APP" || ui_die "Installing $APP on $s failed (see the log)."
done
if [[ "$KIND" != foundation ]]; then
  ui_run "Building the portal ($CORE)" -- provision build "$CORE" || ui_warn "The portal build failed (see the log): fix it, then run: bench build --app $CORE"
fi
workspace_render && ui_ok ".vscode/dev.code-workspace $RENDER_STATUS ($APP added)"

# =============================================================================
# APPS_READ_TOKEN: GitHub's own CI token reads only the repository it runs in.
# The app's CI also reads the platform repository and its hard dependencies,
# and the platform's level-2 CI reads every app: a private one among them
# needs this secret (a token with read access), set by hand.
ui_section "CI access to private repositories"
deps=$(python3 -c 'import ast, sys
for n in ast.parse(open(sys.argv[1]).read()).body:
    t = n.targets[0] if isinstance(n, ast.Assign) else getattr(n, "target", None)
    if getattr(t, "id", "") == "required_apps": print(" ".join(ast.literal_eval(n.value)))' "$APP_DIR/$APP/hooks.py" 2>/dev/null)
visibility_of() { gh api "repos/$1" --jq .visibility 2>/dev/null || echo unknown; }
private_read=(); app_private=false
for r in "$PLATFORM_OWNER/$PLATFORM_REPO" $(for d in $deps; do printf '%s/%s ' "$OWNER" "$d"; done); do
  [[ "$(visibility_of "$r")" == public ]] || private_read+=("$r")
done
[[ "$(visibility_of "$SLUG")" == public ]] || app_private=true
has_secret() { gh secret list --repo "$1" --json name --jq '.[].name' 2>/dev/null | grep -qx APPS_READ_TOKEN; }
need=()   # repositories that need the secret and lack it
if (( ${#private_read[@]} )); then
  if has_secret "$SLUG"; then ui_ok "$SLUG has the APPS_READ_TOKEN secret (its CI reads ${private_read[*]})"
  else need+=("$SLUG"); ui_warn "$SLUG needs the APPS_READ_TOKEN secret: its CI reads the private ${private_read[*]}."; fi
fi
if [[ "$app_private" == true ]]; then
  if has_secret "$PLATFORM_OWNER/$PLATFORM_REPO"; then ui_ok "$PLATFORM_OWNER/$PLATFORM_REPO has the APPS_READ_TOKEN secret (its level-2 CI reads the private $SLUG)"
  else need+=("$PLATFORM_OWNER/$PLATFORM_REPO"); ui_warn "$PLATFORM_OWNER/$PLATFORM_REPO needs the APPS_READ_TOKEN secret: its level-2 CI reads the private $SLUG."; fi
fi
if (( ${#need[@]} == 0 && ${#private_read[@]} == 0 )) && [[ "$app_private" == false ]]; then
  ui_ok "Every repository CI reads is public: no APPS_READ_TOKEN secret needed"
elif (( ${#need[@]} )); then
  steps=("Until then CI fails at 'just setup' (it can't clone the private repositories). Once:"
    "1. Create a fine-grained token: https://github.com/settings/personal-access-tokens/new — resource owner $OWNER, repository access 'All repositories' (covers apps created later), permissions 'Contents: Read-only' only. Not your gh login token: it can write and administer every repository.")
  n=2
  for r in "${need[@]}"; do
    steps+=("$n. Add it to $r: gh secret set APPS_READ_TOKEN --repo $r (paste the token when asked), or https://github.com/$r/settings/secrets/actions/new")
    n=$((n + 1))
  done
  steps+=("$n. Re-run the failed CI run of ${need[0]} (Actions tab › Re-run jobs). The same token serves every repository: add it to each new private app too.")
  ui_box "APPS_READ_TOKEN — what to do:" "${steps[@]}"
fi

ui_box "Next steps:" \
  "1. Work in frappe-bench/apps/$APP: just setup, then just ci (see its README)." \
  "2. When it conforms (docs/conformance.md empty, CI green): tag v0.1.0 and add it to platform.lock by hand (playbook new-feature-app, step 9)."
