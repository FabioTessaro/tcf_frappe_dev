#!/usr/bin/env bash
# new-platform.sh — create the platform repository, or check it out, next to
# the bench in ./platform (guide chapter 500; one per GitHub owner).
#
# Usage: ./new-platform.sh [options]
#
#   ./platform exists          checks that its origin is the platform repository
#   repository exists on GitHub clones it into ./platform
#   neither                    scaffolds it in ./platform from
#                              bootstrap/templates/platform (current tool
#                              versions and image digests, pinned), creates the
#                              GitHub repository, pushes, and applies the
#                              repository settings the GitHub plan allows
# Then, in every case: PLATFORM_URL is saved in .env, the git hooks are
# installed and ./platform is added to the VS Code workspace.
#
# Options:
#   --answers FILE   take answers from FILE (KEY=VALUE): PLATFORM_OWNER,
#                    PLATFORM_REPO (default platform), PLATFORM_VISIBILITY (private|public),
#                    PLATFORM_LICENSE (proprietary|mit|apache-2.0|agpl-3.0|
#                    gpl-3.0), PLATFORM_COPYRIGHT, FRAPPE_VERSION (a tag).
#                    See bootstrap/templates/new-platform.answers.example.conf
#   --dir DIR        checkout folder (default: ./platform)
#   --no-push        scaffold and commit locally only: no GitHub calls (tests)
#   -y, --yes        don't ask for the final confirmation
#   --trace          also write a bash execution trace into the log
#   -h, --help       show this help
#
# Needs: git, docker (image digests), python3, gh logged in (./install.sh, git
# component). Log: logs/new-platform-<timestamp>.log
set -o pipefail
# shellcheck source=bootstrap/lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/apps.sh
source "$LIB_DIR/apps.sh"
# shellcheck source=bootstrap/lib/project.sh
source "$LIB_DIR/project.sh"
# shellcheck source=bootstrap/lib/scaffold.sh
source "$LIB_DIR/scaffold.sh"

ANSWERS_FILE=""; PLATFORM_DIR="$REPO_ROOT/platform"; NO_PUSH=false; ASSUME_YES=false
for a in "$@"; do [[ "$a" == -h || "$a" == --help ]] && { usage_from_header "$0"; exit 0; }; done
script_init new-platform "$@"
set -- "${SCRIPT_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --answers) ANSWERS_FILE="${2:-}"; shift ;;
    --answers=*) ANSWERS_FILE="${1#*=}" ;;
    --dir) PLATFORM_DIR="${2:-}"; shift ;;
    --dir=*) PLATFORM_DIR="${1#*=}" ;;
    --no-push) NO_PUSH=true ;;
    -y|--yes) ASSUME_YES=true ;;
    *) ui_die "Unknown option: $1" "See ./new-platform.sh --help" ;;
  esac
  shift
done
[[ "$PLATFORM_DIR" == /* ]] || PLATFORM_DIR="$REPO_ROOT/$PLATFORM_DIR"

declare -A ANS=() CUR=() V=()
if [[ -n "$ANSWERS_FILE" ]]; then
  [[ -f "$ANSWERS_FILE" ]] || ui_die "Answers file not found: $ANSWERS_FILE"
  env_parse "$ANSWERS_FILE" ANS
fi
[[ -f "$ENV_FILE" ]] && env_parse "$ENV_FILE" CUR
has_answer() { [[ -n "${ANS[$1]+x}" ]]; }
need_tty_for() {
  [[ "$UI_TTY_IN" == true ]] && return 0
  ui_die "No terminal to ask for $2 ($1)." "Add $1=… to the answers file (--answers)."
}

ui_banner "New platform repository" "create it, or check it out into ${PLATFORM_DIR#"$REPO_ROOT"/}"

# =============================================================================
ui_section "Prerequisites"
for t in git python3 docker; do command -v "$t" >/dev/null 2>&1 || ui_die "$t is not installed." "Run ./install.sh."; done
ui_ok "git, python3 and docker are available"
if [[ "$NO_PUSH" == false ]]; then
  command -v gh >/dev/null 2>&1 || ui_die "gh (GitHub CLI) is not installed." "Run ./install.sh --components base,git"
  ui_run --quiet-fail "Checking the GitHub CLI login" -- gh_logged_in \
    || ui_die "gh is not logged in to GitHub." "Run ./install.sh --components git (or: gh auth login --git-protocol ssh --web)"
  GH_USER=$(gh api user --jq .login); ui_ok "gh is logged in as $GH_USER"
else
  GH_USER=""; ui_note "--no-push: nothing is created or read on GitHub."
fi

# =============================================================================
ui_section "Repository"
def_owner=$(owner_from_prefix "${CUR[CUSTOM_APPS_GIT_PREFIX]:-}" || true); def_owner="${def_owner:-$GH_USER}"
if has_answer PLATFORM_OWNER; then OWNER="${ANS[PLATFORM_OWNER]}"
else
  need_tty_for PLATFORM_OWNER "the GitHub owner"
  ui_input --default "$def_owner" --validate valid_gh_name --error "a GitHub user or organisation name" \
    "GitHub owner (user or organisation) of the platform repository"
  OWNER="$UI_VALUE"
fi
valid_gh_name "$OWNER" || ui_die "Invalid GitHub owner '$OWNER'."
def_repo=platform
[[ "${CUR[PLATFORM_URL]:-}" =~ /([^/]+)\.git$ ]] && def_repo="${BASH_REMATCH[1]}"
if has_answer PLATFORM_REPO; then REPO="${ANS[PLATFORM_REPO]}"
else
  need_tty_for PLATFORM_REPO "the repository name"
  ui_input --default "$def_repo" --validate valid_gh_name --error "letters, digits, '.', '_' and '-' only" \
    "Name of the platform repository (checked out in ./platform whatever its name)"
  REPO="$UI_VALUE"
fi
valid_gh_name "$REPO" || ui_die "Invalid repository name '$REPO'."
SLUG="$OWNER/$REPO"; URL="git@github.com:$SLUG.git"
ui_kv "Repository" "$SLUG"; ui_kv "Checkout" "${PLATFORM_DIR#"$REPO_ROOT"/}"

# --- current state: the script converges from any of them (idempotent) -----------
#   local   none | unpublished (scaffold not linked to GitHub yet) | linked
#   GitHub  missing | empty (created, nothing pushed) | populated
LOCAL=none; REMOTE=skipped
if [[ -e "$PLATFORM_DIR" ]]; then
  if [[ -d "$PLATFORM_DIR/.git" ]]; then
    origin=$(git -C "$PLATFORM_DIR" remote get-url origin 2>/dev/null || true)
    if [[ -z "$origin" ]]; then LOCAL=unpublished
    elif [[ "$origin" == "$URL" || "$origin" == "https://github.com/$SLUG"* ]]; then LOCAL=linked
    else ui_die "${PLATFORM_DIR#"$REPO_ROOT"/} is a checkout of '$origin', not $SLUG." "Move it away or choose its owner."
    fi
  elif [[ -n "$(ls -A "$PLATFORM_DIR" 2>/dev/null)" ]]; then
    ui_die "${PLATFORM_DIR#"$REPO_ROOT"/} exists and is not a git checkout." "Move it away and run again."
  fi
fi
if [[ "$NO_PUSH" == false ]]; then
  if ui_run --quiet-fail "Looking for $SLUG on GitHub" -- gh_repo_exists "$SLUG"; then
    if gh api "repos/$SLUG/branches/main" --silent >/dev/null 2>&1; then REMOTE=populated; else REMOTE=empty; fi
  else
    REMOTE=missing
  fi
fi
[[ "$LOCAL" == unpublished && "$REMOTE" == populated ]] && ui_die \
  "${PLATFORM_DIR#"$REPO_ROOT"/} holds a local scaffold, but $SLUG already has content on GitHub." \
  "Move ${PLATFORM_DIR#"$REPO_ROOT"/} away and run again to clone the repository."
SCAFFOLD=false; CLONE=false; CREATED=false
case "$LOCAL:$REMOTE" in
  none:populated) CLONE=true ;;
  none:*) SCAFFOLD=true ;;
esac
case "$LOCAL" in
  none) ui_kv "Local checkout" "none — will be $([[ $CLONE == true ]] && echo cloned || echo scaffolded)" ;;
  unpublished) ui_kv "Local checkout" "present, not linked to GitHub yet" ;;
  linked) ui_kv "Local checkout" "present, linked to $SLUG" ;;
esac
case "$REMOTE" in
  missing) ui_kv "GitHub" "doesn't exist yet — will be created" ;;
  empty) ui_kv "GitHub" "exists but empty — main will be pushed" ;;
  populated) ui_kv "GitHub" "exists" ;;
  skipped) ui_kv "GitHub" "not checked (--no-push)" ;;
esac

# =============================================================================
VISIBILITY=""
if [[ "$REMOTE" == missing ]]; then
  ui_section "Visibility"
  if has_answer PLATFORM_VISIBILITY; then VISIBILITY="${ANS[PLATFORM_VISIBILITY]}"
  else
    need_tty_for PLATFORM_VISIBILITY "the visibility"
    ui_select "Visibility of $SLUG" "private::Private" "public::Public::anyone can read it" || exit 1
    VISIBILITY="$UI_VALUE"
  fi
  [[ "$VISIBILITY" == private || "$VISIBILITY" == public ]] || ui_die "PLATFORM_VISIBILITY must be private or public."
fi

if [[ "$SCAFFOLD" == true ]]; then
  ui_section "Choices"

  if has_answer PLATFORM_LICENSE; then LICENSE_KEY="${ANS[PLATFORM_LICENSE]}"
  else
    need_tty_for PLATFORM_LICENSE "the licence"
    ui_select "Licence of $SLUG" "${LICENSE_CHOICES[@]}" || exit 1
    LICENSE_KEY="$UI_VALUE"
  fi
  [[ -n "$(license_name "$LICENSE_KEY")" ]] || ui_die "Unknown licence '$LICENSE_KEY'."
  if has_answer PLATFORM_COPYRIGHT; then HOLDER="${ANS[PLATFORM_COPYRIGHT]}"
  else
    need_tty_for PLATFORM_COPYRIGHT "the copyright holder"
    ui_input --default "$(git config --global user.name 2>/dev/null)" --validate valid_env_value "Copyright holder"
    HOLDER="$UI_VALUE"
  fi

  # Frappe: an exact tag (platform.lock pins tags and commits).
  FRAPPE_URL=https://github.com/frappe/frappe
  if has_answer FRAPPE_VERSION; then FRAPPE_TAG="${ANS[FRAPPE_VERSION]}"
  else
    need_tty_for FRAPPE_VERSION "the Frappe version"
    while true; do
      pick_version "Frappe" "$FRAPPE_URL" "${CUR[FRAPPE_VERSION]:-}" || exit 1
      [[ "$UI_VALUE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
      ui_warn "'$UI_VALUE' is not a release tag (vX.Y.Z): platform.lock pins tags."
    done
    FRAPPE_TAG="$UI_VALUE"
  fi
  [[ "$FRAPPE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || ui_die "FRAPPE_VERSION must be a release tag like v16.2.0 (got '$FRAPPE_TAG')."
  FRAPPE_MAJOR=$(version_major "$FRAPPE_TAG")

  [[ -n "$VISIBILITY" ]] && ui_kv "Visibility" "$VISIBILITY"
  ui_kv "Licence" "$(license_name "$LICENSE_KEY") — $HOLDER"
  ui_kv "Frappe" "$FRAPPE_TAG"; ui_kv "Guide" "$(guide_version)"
  if [[ "$ASSUME_YES" == false && "$UI_TTY_IN" == true ]]; then
    msg="Create $SLUG"; [[ "$NO_PUSH" == true ]] && msg="Scaffold $SLUG locally (no push)"
    ui_confirm "$msg?" y || { ui_info "Nothing done."; exit 0; }
  fi

  # ===========================================================================
  ui_section "Pinned versions"
  VFILE="$STATE_TMP_DIR/platform-versions.env"; : > "$VFILE"
  _resolve_all() {
    local f="$VFILE"
    resolve_into "$f" FRAPPE_SHA resolve_tag_commit "$FRAPPE_URL" "$FRAPPE_TAG" || return 1
    resolve_into "$f" JUST_VERSION resolve_gh_release casey/just "" || return 1
    resolve_into "$f" GITLEAKS_VERSION resolve_gh_release gitleaks/gitleaks || return 1
    resolve_into "$f" LYCHEE_VERSION resolve_gh_release lycheeverse/lychee lychee-v || return 1
    resolve_into "$f" HADOLINT_VERSION resolve_gh_release hadolint/hadolint || return 1
    resolve_into "$f" TRIVY_VERSION resolve_gh_release aquasecurity/trivy || return 1
    resolve_into "$f" SYFT_VERSION resolve_gh_release anchore/syft || return 1
    resolve_into "$f" COSIGN_VERSION resolve_gh_release sigstore/cosign || return 1
    resolve_into "$f" GIT_CLIFF_VERSION resolve_gh_release orhun/git-cliff || return 1
    resolve_into "$f" UV_VERSION resolve_gh_release astral-sh/uv "" || return 1
    resolve_into "$f" SHELLCHECK_VERSION resolve_gh_release koalaman/shellcheck || return 1
    resolve_into "$f" BUILDX_VERSION resolve_gh_release docker/buildx || return 1
    resolve_into "$f" DOCKER_VERSION resolve_git_tag https://github.com/docker/cli || return 1
    resolve_into "$f" PRE_COMMIT_VERSION resolve_pypi pre-commit || return 1
    resolve_into "$f" MYPY_VERSION resolve_pypi mypy || return 1
    resolve_into "$f" PYDANTIC_VERSION resolve_pypi pydantic || return 1
    resolve_into "$f" IMPORT_LINTER_VERSION resolve_pypi import-linter || return 1
    resolve_into "$f" MARKDOWNLINT_VERSION resolve_npm markdownlint-cli2 || return 1
    resolve_into "$f" RENOVATE_VERSION resolve_npm renovate || return 1
    resolve_into "$f" CHECKOUT_TAG resolve_gh_release actions/checkout "" || return 1
    # shellcheck disable=SC1090
    source "$f" || return 1
    resolve_into "$f" CHECKOUT_SHA resolve_tag_commit https://github.com/actions/checkout "$CHECKOUT_TAG" || return 1
    resolve_into "$f" BENCH_IMAGE resolve_digest frappe/bench:latest || return 1
    resolve_into "$f" BUILD_IMAGE resolve_digest "frappe/build:version-$FRAPPE_MAJOR" || return 1
    resolve_into "$f" BASE_IMAGE resolve_digest "frappe/base:version-$FRAPPE_MAJOR" || return 1
    resolve_into "$f" MARIADB_IMAGE resolve_digest mariadb:11.8 || return 1
    local redis seaweed clam
    redis=$(resolve_hub_tag library/redis '^[0-9]+\.[0-9]+\.[0-9]+-alpine$') || return 1
    resolve_into "$f" REDIS_IMAGE resolve_digest "redis:$redis" || return 1
    seaweed=$(resolve_hub_tag chrislusf/seaweedfs '^[0-9]+\.[0-9]+$') || return 1
    resolve_into "$f" SEAWEEDFS_IMAGE resolve_digest "chrislusf/seaweedfs:$seaweed" || return 1
    clam=$(resolve_hub_tag clamav/clamav '^[0-9]+\.[0-9]+\.[0-9]+$') || return 1
    resolve_into "$f" CLAMAV_IMAGE resolve_digest "clamav/clamav:$clam" || return 1
  }
  ui_run "Resolving current tool versions and image digests" -- _resolve_all \
    || ui_die "Couldn't resolve every version (network?)." "See the log."
  env_parse "$VFILE" V
  for k in FRAPPE_SHA JUST_VERSION TRIVY_VERSION DOCKER_VERSION BENCH_IMAGE BUILD_IMAGE REDIS_IMAGE; do ui_kv "$k" "${V[$k]}"; done
  ui_note "…and $(( ${#V[@]} - 7 )) more, all pinned in the repository (Renovate keeps them current)."

  # ===========================================================================
  ui_section "Scaffold"
  mkdir -p "$PLATFORM_DIR"
  vals=(
    "OWNER=$OWNER" "REPO_NAME=$REPO" "OWNER_LC=${OWNER,,}" "REPO_LC=${REPO,,}" "GUIDE_VERSION=$(guide_version)" "TODAY=$(date +%F)"
    "LICENSE_NAME=$(license_name "$LICENSE_KEY")" "FRAPPE_VERSION=$FRAPPE_TAG" "CI_TAG=pending"
  )
  for k in "${!V[@]}"; do vals+=("$k=${V[$k]}"); done
  _scaffold() {
    scaffold_render_tree "$TEMPLATE_DIR/platform" "$PLATFORM_DIR" "${vals[@]}" || return 1
    cd "$PLATFORM_DIR" || return 1
    # The CI image tag is the hash of its Dockerfile: pin it in the workflows.
    local tag; tag=$(sha256sum ci-image/Dockerfile | cut -c1-12)
    sed -i "s#ghcr.io/${OWNER,,}/ci:pending#ghcr.io/${OWNER,,}/ci:$tag#g" .github/workflows/*.yml
    # This repository uses its own shared configuration (files of kind "all").
    awk '!/^#/ && NF == 3 && $3 == "all" {print $1, $2}' shared-config/files.txt | while read -r s d; do
      cp "shared-config/$s" "$d"
    done
    chmod 755 tools/lock.py tools/contracts.py
  }
  ui_run "Rendering bootstrap/templates/platform" -- _scaffold || ui_die "Scaffolding failed."
  if [[ "$NO_PUSH" == true && "$LICENSE_KEY" != proprietary ]] && ! command -v gh >/dev/null 2>&1; then
    ui_warn "--no-push without gh: LICENSE written as proprietary placeholder."; LICENSE_KEY=proprietary
  fi
  ui_run "Writing the licence ($(license_name "$LICENSE_KEY"))" -- \
    license_write "$LICENSE_KEY" "$HOLDER" "$(date +%Y)" "$PLATFORM_DIR/LICENSE" || ui_die "Writing LICENSE failed."
  _commit() {
    cd "$PLATFORM_DIR" && git init -q -b main && git add -A \
      && git -c commit.gpgsign=false commit -q --no-verify -m "chore: scaffold $REPO (guide $(guide_version))"
  }
  ui_run "Creating the first commit" -- _commit || ui_die "git commit failed."
  ui_ok "Scaffolded $(git -C "$PLATFORM_DIR" ls-files | wc -l) files in ${PLATFORM_DIR#"$REPO_ROOT"/}"

fi

# =============================================================================
if [[ "$CLONE" == true ]]; then
  ui_section "Checkout"
  mkdir -p "$(dirname "$PLATFORM_DIR")"
  ui_run "Cloning $SLUG" -- git clone -q "$URL" "$PLATFORM_DIR" || ui_die "git clone failed." "Check that $URL accepts your SSH key."
fi

# =============================================================================
# GitHub: create what is missing, push only into an empty repository (later
# commits go through pull requests), then (re)apply every setting.
if [[ "$NO_PUSH" == false ]]; then
  ui_section "GitHub"
  if [[ "$REMOTE" == missing ]]; then
    ui_run "Creating $SLUG ($VISIBILITY)" -- gh repo create "$SLUG" "--$VISIBILITY" \
      --description "Platform repository: release definition, CI image, shared configuration" \
      || ui_die "gh repo create failed."
    REMOTE=empty; CREATED=true
  else
    ui_ok "$SLUG exists"
  fi
  if [[ -z "$(git -C "$PLATFORM_DIR" remote get-url origin 2>/dev/null)" ]]; then
    git -C "$PLATFORM_DIR" remote add origin "$URL" && ui_ok "origin → $URL"
  fi
  if [[ "$REMOTE" == empty ]]; then
    ui_run "Pushing main" -- git -C "$PLATFORM_DIR" push -q -u origin main \
      || ui_die "git push failed." "Check that $URL accepts your SSH key, then run ./new-platform.sh again."
    CREATED=true
  else
    ui_run --quiet-fail "Fetching origin" -- git -C "$PLATFORM_DIR" fetch -q origin || ui_warn "Couldn't fetch origin."
    ahead=$(git -C "$PLATFORM_DIR" rev-list --count origin/main..main 2>/dev/null || echo 0)
    behind=$(git -C "$PLATFORM_DIR" rev-list --count main..origin/main 2>/dev/null || echo 0)
    if (( ahead > 0 )); then ui_note "Local main has $ahead commit(s) not on GitHub: not pushed — changes go through pull requests."; fi
    if (( behind > 0 )); then ui_note "Local main is $behind commit(s) behind GitHub: git -C ${PLATFORM_DIR#"$REPO_ROOT"/} pull"; fi
    (( ahead == 0 && behind == 0 )) && ui_ok "main is in sync with GitHub"
  fi
  gh_apply_repo_settings "$SLUG" ci-image checks
fi

# =============================================================================
ui_section "Development environment"
if command -v pre-commit >/dev/null 2>&1 && [[ -f "$PLATFORM_DIR/.pre-commit-config.yaml" ]]; then
  ui_run "Installing the git hooks of ${PLATFORM_DIR#"$REPO_ROOT"/}" -- bash -c "cd '$PLATFORM_DIR' && pre-commit install" \
    || ui_warn "pre-commit install failed in ${PLATFORM_DIR#"$REPO_ROOT"/}."
fi
if [[ "$PLATFORM_DIR" != "$REPO_ROOT/platform" ]]; then
  ui_note "Custom --dir: PLATFORM_URL and the VS Code workspace are left as they are."
elif [[ ! -f "$ENV_FILE" ]]; then
  ui_warn "No .env yet: run ./setup.sh, then ./new-platform.sh again to record PLATFORM_URL."
elif [[ "$NO_PUSH" == true ]]; then
  ui_note "--no-push: PLATFORM_URL not recorded."
else
  env_set_key PLATFORM_URL "$URL" && ui_ok "PLATFORM_URL recorded in .env"
  workspace_render && ui_ok ".vscode/dev.code-workspace $RENDER_STATUS (platform folder added)"
fi

if [[ "$CREATED" == true ]]; then
  pkg_url="https://github.com/$( gh_owner_is_org "$OWNER" && echo "orgs/$OWNER" || echo "users/$OWNER")/packages/container/ci/settings"
  ui_box "One-time steps on GitHub (the API can't do them):" \
    "1. After the first CI run, make the CI image package public: $pkg_url" \
    "2. Secrets that activate the inactive steps (Settings › Secrets and variables › Actions): APPS_READ_TOKEN, RENOVATE_TOKEN, COSIGN_PRIVATE_KEY + COSIGN_PASSWORD; DEPLOY_HOST + DEPLOY_SSH_KEY in the staging and production environments."
fi
ui_info "Next: build the CI image on this host — cd ${PLATFORM_DIR#"$REPO_ROOT"/} && just ci-image-build && just ci"
