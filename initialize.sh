#!/usr/bin/env bash
# initialize.sh — build and start the development environment from .env.
#
# Usage: ./initialize.sh [options]
#
# Steps (each one checks first and only does what is missing):
#   1. configuration   read .env (stops with a clear message if missing)
#   2. VS Code Server  choose the build to pre-seed (menu: detected on this
#                      host / latest stable / a specific commit / skip)
#   3. containers      render docker-compose.yml, pull images, start them
#   4. VS Code Server  copy the chosen build into the frappe container
#   5. container tools apt packages; uv, pre-commit and the developer toolchain
#                      (ruff, mypy, shellcheck, gitleaks, lychee, hadolint,
#                      just, trivy, markdownlint-cli2); wait for MariaDB,
#                      SeaweedFS and ClamAV; check the MariaDB root password
#   6. bench           bench init with FRAPPE_VERSION
#   7. apps            fetch default apps and custom apps
#   8. sites           create <site>, test.<site> (all apps) and
#                      test-minimal.<site> (core app only), install the apps,
#                      apply bootstrap/templates/site-config/*.json.template
#   9. buckets         create the SeaweedFS buckets
#  10. assets          bench build, app by app: a failing app is reported and
#                      skipped, so Frappe and the other apps still work
#  11. extras          Claude Code (optional), VS Code workspace + extensions
#
# When the bench differs from .env (other versions, removed apps, renamed
# site, changed passwords) initialize.sh explains the difference and asks
# before changing or removing anything ("reconcile").
#
# Options:
#   --vscode-detect      use the VS Code commit detected on this host
#   --vscode-latest      use the latest stable release (see --platform)
#   --vscode-commit HASH use this 40-character commit
#   --skip-vscode        don't pre-seed the VS Code Server
#   --platform NAME      client platform for --vscode-latest: win32-x64-user,
#                        win32-arm64-user, darwin-universal, linux-x64,
#                        linux-arm64, server-linux-x64
#   --with-claude        install Claude Code in the container (remembered)
#   --no-claude          don't (remembered)
#   --reconcile MODE     ask (default with a terminal) | apply (do every
#                        proposed change) | skip (change nothing, only warn;
#                        default without a terminal)
#   --no-build           skip `bench build`
#   --no-extensions      don't install VS Code extensions in the container
#   --trace              also write a bash execution trace into the log
#   -h, --help           show this help
#
# Log: logs/initialize-<timestamp>.log
set -o pipefail
# shellcheck source=bootstrap/lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/apps.sh
source "$LIB_DIR/apps.sh"
# shellcheck source=bootstrap/lib/project.sh
source "$LIB_DIR/project.sh"
# shellcheck source=bootstrap/lib/vscode.sh
source "$LIB_DIR/vscode.sh"

VS_WANT=""; VS_WANT_COMMIT=""; VS_PLATFORM=""
WITH_CLAUDE=""; RECONCILE=""; DO_BUILD=true; DO_EXTENSIONS=true
INIT_PREFS="$STATE_DIR/initialize.conf"

for a in "$@"; do [[ "$a" == -h || "$a" == --help ]] && { usage_from_header "$0"; exit 0; }; done
script_init initialize "$@"
set -- "${SCRIPT_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vscode-detect) VS_WANT=detect ;;
    --vscode-latest) VS_WANT=latest ;;
    --vscode-commit) VS_WANT=commit; VS_WANT_COMMIT="${2:-}"; shift ;;
    --skip-vscode) VS_WANT=skip ;;
    --platform) VS_PLATFORM="${2:-}"; shift ;;
    --with-claude) WITH_CLAUDE=1 ;;
    --no-claude) WITH_CLAUDE=0 ;;
    --reconcile) RECONCILE="${2:-}"; shift ;;
    --reconcile=*) RECONCILE="${1#*=}" ;;
    --no-build) DO_BUILD=false ;;
    --no-extensions) DO_EXTENSIONS=false ;;
    *) ui_die "Unknown option: $1" "See ./initialize.sh --help" ;;
  esac
  shift
done
if [[ -z "$RECONCILE" ]]; then
  if [[ "$UI_TTY_IN" == true ]]; then RECONCILE=ask; else RECONCILE=skip; fi
fi
[[ "$RECONCILE" =~ ^(ask|apply|skip)$ ]] || ui_die "--reconcile must be ask, apply or skip."

ui_banner "frappe-dev · initialize" "build & start the environment"
UI_STEP_TOTAL=11
FAILED_CUSTOM=(); FAILED_BUILDS=(); SKIPPED_RECONCILE=()

# reconcile QUESTION DETAIL — 0 = apply the change.
reconcile() {
  ui_warn "$1"
  [[ -n "${2:-}" ]] && ui_note "$2"
  case "$RECONCILE" in
    apply) ui_note "--reconcile apply: doing it."; return 0 ;;
    skip) ui_note "--reconcile skip: left as it is."; SKIPPED_RECONCILE+=("$1"); return 1 ;;
  esac
  ui_select "What should initialize.sh do?" "apply::Apply the change" "keep::Keep things as they are (only warn)" || exit 1
  [[ "$UI_VALUE" == apply ]] && return 0
  SKIPPED_RECONCILE+=("$1"); return 1
}

# pstep [--optional] LABEL -- ARGS — provision.sh step under a spinner, with
# "::warn::" lines shown as warnings. Non-optional failures stop the script.
pstep() {
  local optional=false
  [[ "$1" == --optional ]] && { optional=true; shift; }
  local label="$1"; shift; [[ "$1" == -- ]] && shift
  local rc=0
  ui_run "$label" -- provision "$@" || rc=$?
  local w
  while IFS= read -r w; do ui_warn "${w#::warn:: }"; done < <(grep '^::warn::' "$UI_LAST_OUTPUT" 2>/dev/null)
  if (( rc != 0 )) && [[ "$optional" == false ]]; then
    ui_die "$label failed." "Details: ${LOG_FILE_REL}  —  fix the cause and run ./initialize.sh again (finished steps are skipped)."
  fi
  return "$rc"
}

# =============================================================================
ui_section "Configuration"
env_require
catalog_load
missing=()
for k in SITE_NAME TEST_SITE_NAME ADMIN_PASSWORD MARIADB_ROOT_PASSWORD FRAPPE_VERSION \
         SEAWEEDFS_ACCESS_KEY SEAWEEDFS_SECRET_KEY MARIADB_EXPOSE_PORT; do
  [[ -n "${ENV[$k]:-}" ]] || missing+=("$k")
done
read -r -a DEFAULT_LIST <<< "${ENV[DEFAULT_APPS]:-}"
for a in "${DEFAULT_LIST[@]}"; do
  [[ -n "${CAT_REPO[$a]:-}" ]] || ui_die "DEFAULT_APPS contains '$a', which is not in bootstrap/templates/apps.catalog."
  k=$(app_version_key "$a"); [[ -n "${ENV[$k]:-}" ]] || missing+=("$k")
done
# Custom apps: CUSTOM_APPS (empty until ./new-app.sh creates the first one).
# Older .env files may still say APPS_MODE=shell: no custom apps then.
CUSTOM_LIST=()
[[ "${ENV[APPS_MODE]:-}" == shell ]] || read -r -a CUSTOM_LIST <<< "${ENV[CUSTOM_APPS]:-}"
(( ${#CUSTOM_LIST[@]} )) && [[ -z "${ENV[CORE_APP]:-}" ]] && missing+=(CORE_APP)
if cfg_meet_enabled ENV; then
  for k in JWT_SECRET WEBRTC_ANNOUNCED_IP; do [[ -n "${ENV[$k]:-}" ]] || missing+=("$k"); done
fi
(( ${#missing[@]} == 0 )) || ui_die ".env is incomplete: ${missing[*]}" "Run ./setup.sh to complete it."
SITE="${ENV[SITE_NAME]}"; TEST_SITE="${ENV[TEST_SITE_NAME]}"
# Older .env files don't have it: derived from the site name.
MIN_SITE="${ENV[TEST_MINIMAL_SITE_NAME]:-test-minimal.$SITE}"
ui_ok ".env loaded: Frappe ${ENV[FRAPPE_VERSION]}, sites $SITE + $TEST_SITE + $MIN_SITE"
ui_note "default apps: ${DEFAULT_LIST[*]:-none} · custom apps: ${CUSTOM_LIST[*]:-none yet (./new-app.sh)}"

[[ -f "$HOME/.gitconfig" ]] || ui_die "$HOME/.gitconfig doesn't exist (it is mounted into the container)." "Run ./install.sh (git component)."
[[ -d "$HOME/.ssh" ]] || ui_die "$HOME/.ssh doesn't exist (it is mounted into the container)." "Run ./install.sh (git component)."
[[ "$(id -u)" == 1000 ]] || ui_warn "Your uid is $(id -u) but the container user's is 1000: ~/.ssh may not be readable in the container."

# Claude Code preference (asked once, remembered in .state/initialize.conf).
declare -A PREFS=()
env_parse "$INIT_PREFS" PREFS 2>/dev/null || true
if [[ -z "$WITH_CLAUDE" ]]; then
  if [[ -n "${PREFS[WITH_CLAUDE]:-}" ]]; then
    WITH_CLAUDE="${PREFS[WITH_CLAUDE]}"
    ui_note "Claude Code in the container: $([[ $WITH_CLAUDE == 1 ]] && echo yes || echo no) (remembered — change with --with-claude / --no-claude)"
  else
    if [[ "$UI_TTY_IN" != true ]]; then ui_die "Pass --with-claude or --no-claude (no terminal to ask)."; fi
    ui_select "Install the Claude Code CLI inside the container?" \
      "1::Yes — install Claude Code" "0::No" || exit 1
    WITH_CLAUDE="$UI_VALUE"
  fi
fi
printf 'WITH_CLAUDE=%s\n' "$WITH_CLAUDE" > "$INIT_PREFS"

# =============================================================================
ui_section "VS Code Server version"
docker_require
vscode_choose initialize || { ui_info "Cancelled."; exit 1; }
case "$VS_SOURCE" in
  skip) ui_note "Not pre-seeding the VS Code Server (run ./reseed.sh later)." ;;
  *) ui_ok "VS Code Server ${VS_COMMIT:0:12}… (${VS_SOURCE}${VS_VERSION:+, $VS_VERSION})" ;;
esac

# =============================================================================
ui_section "Containers"
compose_render ENV || ui_die "Couldn't render docker-compose.yml."
ui_ok "docker-compose.yml $RENDER_STATUS"
# pull_images — pulls every image of the compose file in parallel and prints
# a status line whenever progress changes (the spinner shows the latest one):
#   "2/5 images done · frappe/bench:latest 14/27 layers"
pull_images() {
  local dir="$STATE_TMP_DIR/pull" i names=() total ready line last="" nfail=0
  mkdir -p "$dir"
  mapfile -t names < <(dc config --images 2>/dev/null | sort -u)
  total=${#names[@]}
  (( total )) || { echo "no images found in docker-compose.yml"; return 1; }
  echo "pulling $total images in parallel: ${names[*]}"
  for i in "${!names[@]}"; do
    ( dk pull "${names[i]}" > "$dir/$i.log" 2>&1; echo $? > "$dir/$i.rc" ) &
  done
  while true; do
    ready=0; line=""
    for i in "${!names[@]}"; do
      if [[ -f "$dir/$i.rc" ]]; then ready=$((ready + 1)); continue; fi
      local layers doneL
      layers=$(grep -oE '^[0-9a-f]{12}: ' "$dir/$i.log" 2>/dev/null | sort -u | wc -l)
      doneL=$(grep -E '^[0-9a-f]{12}: (Pull complete|Already exists)' "$dir/$i.log" 2>/dev/null | cut -d: -f1 | sort -u | wc -l)
      if (( layers )); then line+=" · ${names[i]##*/} $doneL/$layers layers"; else line+=" · ${names[i]##*/} starting"; fi
    done
    line="$ready/$total images done$line"
    [[ "$line" != "$last" ]] && { echo "$line"; last="$line"; }
    (( ready == total )) && break
    sleep 1
  done
  for i in "${!names[@]}"; do
    if [[ "$(cat "$dir/$i.rc")" != 0 ]]; then
      echo "FAILED  ${names[i]}: $(tail -n 1 "$dir/$i.log")"; nfail=$((nfail + 1))
    elif grep -q 'Image is up to date' "$dir/$i.log"; then
      echo "up to date  ${names[i]}"
    else
      echo "downloaded  ${names[i]}"
    fi
  done
  return "$nfail"
}
ui_run "Pulling images" -- pull_images || ui_warn "Some images couldn't be pulled; local copies are used if present (see the log)."
ui_run "Starting containers" -- dc up -d --remove-orphans || ui_die "docker compose up failed." "See ${LOG_FILE_REL}"
running=$(project_running_services | paste -sd' ')
ui_ok "Running: $running"
# =============================================================================
ui_section "VS Code Server in the container"
if [[ "$VS_SOURCE" == skip ]]; then
  ui_note "Skipped."
else
  vscode_seed "$VS_COMMIT" || ui_warn "VS Code Server not pre-seeded — the first attach downloads it itself (or run ./reseed.sh)."
fi

# =============================================================================
ui_section "Container tools"
ui_run "System packages" -- cx_root bash "$CONTAINER_WORKSPACE/bootstrap/container/provision.sh" system-root \
  || ui_die "Installing the container's system packages failed." "See ${LOG_FILE_REL}"
pstep "Developer tools (uv, pre-commit, ruff, mypy, gitleaks, just, …)" -- system-user
pstep "Waiting for MariaDB and SeaweedFS" -- wait-services "$SERVICE_WAIT_TIMEOUT"
# Not fatal: the bench works without the antivirus while clamd is starting.
pstep --optional "Waiting for ClamAV" -- wait-clamav "$SERVICE_WAIT_TIMEOUT" \
  || ui_warn "ClamAV isn't answering yet — it keeps starting in the background (docker logs ${COMPOSE_PROJECT_NAME}-clamav-1)."

if ! ui_run --quiet-fail "Checking the MariaDB root password" -- provision db-auth; then
  declare -A SNAP=(); env_parse "$SNAPSHOT_FILE" SNAP 2>/dev/null || true
  old="${SNAP[MARIADB_ROOT_PASSWORD]:-}"
  if [[ -n "$old" && "$old" != "${ENV[MARIADB_ROOT_PASSWORD]}" ]]; then
    log_add_secret "$old"
    if reconcile "MariaDB still uses the previous root password." "The database volume was created with the old password; it can be changed to the one in .env."; then
      _set_db_pw() { printf '%s\n' "$old" | provision db-root-password; }
      ui_run "Changing the MariaDB root password" -- _set_db_pw || ui_die "Couldn't change the MariaDB root password."
    else
      ui_die "MariaDB rejects the root password in .env." "Restore the old password with ./setup.sh, or wipe the database: ./teardown.sh --volumes=mariadb"
    fi
  else
    ui_die "MariaDB rejects the root password in .env." \
      "The mariadb-data volume was created with another password. Either put that password back (./setup.sh)" \
      "or delete the database volume (data loss): ./teardown.sh --volumes=mariadb"
  fi
fi


# =============================================================================
# Bench state helpers (parsed from `provision.sh inspect`)
declare -A ST_APP=() ST_ORIGIN=() ST_SITE=() REC_APP=() REC_SITE=() REC_PW=()
ST_BENCH=absent; ST_FRAPPE=""; ST_BROKEN=()
inspect_bench() {
  ST_APP=(); ST_ORIGIN=(); ST_SITE=(); REC_APP=(); REC_SITE=(); REC_PW=(); ST_BROKEN=()
  ST_BENCH=absent; ST_FRAPPE=""
  pstep "Inspecting frappe-bench" -- inspect
  local kind name rest
  while read -r kind name rest; do
    case "$kind" in
      bench) ST_BENCH="$name" ;;
      frappe) ST_FRAPPE="$name" ;;
      app) ST_APP[$name]="$rest" ;;
      app-origin) ST_ORIGIN[$name]="$rest" ;;
      site) ST_SITE[$name]="$rest" ;;
      site-broken) ST_BROKEN+=("$name") ;;
      record)
        local rk rn rv; read -r rk rn rv <<< "$name $rest"
        case "$rk" in app) REC_APP[$rn]="$rv" ;; site) REC_SITE[$rn]="$rv" ;; adminpw) REC_PW[$rn]="$rv" ;; esac ;;
    esac
  done < "$UI_LAST_OUTPUT"
  log_line "inspect: bench=$ST_BENCH frappe=$ST_FRAPPE apps=${!ST_APP[*]} sites=${!ST_SITE[*]} broken=${ST_BROKEN[*]}"
}

# =============================================================================
ui_section "Bench"
inspect_bench
if [[ "$ST_BENCH" == present && -n "$ST_FRAPPE" && "$ST_FRAPPE" != "${ENV[FRAPPE_VERSION]}" ]]; then
  if reconcile "frappe-bench uses Frappe $ST_FRAPPE but .env asks for ${ENV[FRAPPE_VERSION]}." \
       "Rebuilding drops the sites (their data is lost) and recreates frappe-bench from scratch. Custom-app clones are deleted too: push your work first!"; then
    if [[ "$RECONCILE" == ask ]]; then
      ui_confirm_typed "Really delete frappe-bench and its sites?" "REBUILD" || ui_die "Cancelled — nothing was changed."
    fi
    pstep "Rebuilding frappe-bench with Frappe ${ENV[FRAPPE_VERSION]} (takes a while)" -- bench-rebuild
  fi
else
  pstep "Initializing frappe-bench with Frappe ${ENV[FRAPPE_VERSION]} (first time takes a while)" -- bench-init
fi
inspect_bench

# =============================================================================
ui_section "Apps"
SWITCHED=false
for a in "${DEFAULT_LIST[@]}"; do
  k=$(app_version_key "$a"); want="${ENV[$k]}"
  if [[ -z "${ST_APP[$a]+x}" ]]; then
    pstep "Fetching $a $want" -- get-app "$a" "${CAT_REPO[$a]}" "$want" default
  elif [[ "${ST_APP[$a]}" != "$want" ]]; then
    if reconcile "$a is at ${ST_APP[$a]:-unknown} but .env asks for $want." "The app is switched to $want and the sites are migrated."; then
      pstep "Switching $a to $want" -- switch-app "$a" "$want"; SWITCHED=true
    fi
  else
    ui_ok "$a $want is present"
  fi
done
for a in "${CUSTOM_LIST[@]}"; do
  url=$(cfg_custom_url ENV "$a")
  if [[ -z "${ST_APP[$a]+x}" ]]; then
    pstep --optional "Cloning custom app $a" -- get-app "$a" "$url" "" custom || {
      ui_error "Custom app $a couldn't be cloned from $url — continuing without it."; FAILED_CUSTOM+=("$a"); }
  else
    if [[ -n "${ST_ORIGIN[$a]:-}" && "${ST_ORIGIN[$a]}" != "$url" ]]; then
      if reconcile "apps/$a points to ${ST_ORIGIN[$a]} but .env says $url." "Only the 'origin' remote URL is changed; your checkout stays as it is."; then
        pstep "Updating the origin of $a" -- set-origin "$a" "$url"
      fi
    fi
    ui_ok "Custom app $a is present"
  fi
done
# Apps this tooling installed earlier that are no longer wanted.
for a in "${!REC_APP[@]}"; do
  [[ "$a" == frappe ]] && continue
  contains "$a" "${DEFAULT_LIST[@]}" "${CUSTOM_LIST[@]}" && continue
  [[ -n "${ST_APP[$a]+x}" ]] || continue
  if reconcile "$a is installed but no longer in .env." "It is uninstalled from every site (its data is deleted) and its code is moved to frappe-bench/archived/apps."; then
    for s in "${!ST_SITE[@]}"; do
      [[ ",${ST_SITE[$s]}," == *",$a,"* ]] && pstep "Uninstalling $a from $s" -- site-uninstall "$s" "$a"
    done
    pstep "Removing $a from the bench" -- remove-app "$a"
  fi
done
for a in "${!ST_APP[@]}"; do
  contains "$a" "${DEFAULT_LIST[@]}" "${CUSTOM_LIST[@]}" && continue
  [[ -n "${REC_APP[$a]+x}" ]] && continue
  ui_warn "apps/$a is in the bench but not in .env (added by hand?) — left untouched."
done

# =============================================================================
ui_section "Sites"
inspect_bench
for s in "${!REC_SITE[@]}"; do
  [[ "$s" == "$SITE" || "$s" == "$TEST_SITE" || "$s" == "$MIN_SITE" ]] && continue
  [[ -n "${ST_SITE[$s]+x}" ]] || contains "$s" "${ST_BROKEN[@]}" || continue
  if reconcile "Site $s is no longer in .env (now: $SITE / $TEST_SITE / $MIN_SITE)." "The site and its database are deleted."; then
    pstep "Dropping site $s" -- site-drop "$s"
  fi
done
for s in "$SITE" "$TEST_SITE" "$MIN_SITE"; do
  kind="main"; [[ "$s" == "$TEST_SITE" || "$s" == "$MIN_SITE" ]] && kind="test"
  force=""
  if contains "$s" "${ST_BROKEN[@]}"; then
    if reconcile "Site $s exists but doesn't respond (broken database?)." "It is recreated from scratch (its data is lost)."; then force=--force
    else ui_warn "Skipping broken site $s."; continue; fi
  fi
  pstep "Site $s" -- site-ensure "$s" "$kind" $force
done
inspect_bench
INSTALL_ORDER=("${DEFAULT_LIST[@]}")
for a in "${CUSTOM_LIST[@]}"; do contains "$a" "${FAILED_CUSTOM[@]}" || INSTALL_ORDER+=("$a"); done
for s in "$SITE" "$TEST_SITE" "$MIN_SITE"; do
  [[ -n "${ST_SITE[$s]+x}" ]] || continue
  site_apps=("${INSTALL_ORDER[@]}")
  if [[ "$s" == "$MIN_SITE" ]]; then
    # Minimal test site: Frappe + the core app only. The app under test and its
    # hard dependencies are installed on it by hand when needed.
    site_apps=()
    core="${ENV[CORE_APP]:-}"
    [[ -n "$core" ]] && contains "$core" "${INSTALL_ORDER[@]}" && site_apps=("$core")
  fi
  for a in "${site_apps[@]}"; do
    if [[ ",${ST_SITE[$s]}," == *",$a,"* ]]; then log_line "$a already installed on $s"; continue; fi
    if contains "$a" "${CUSTOM_LIST[@]}"; then
      pstep --optional "Installing $a on $s" -- site-install "$s" "$a" || {
        ui_error "Custom app $a couldn't be installed on $s — continuing without it."; FAILED_CUSTOM+=("$a@$s"); }
    else
      pstep "Installing $a on $s" -- site-install "$s" "$a"
    fi
  done
  ui_ok "Apps installed on $s"
  pw_hash=$(printf '%s' "${ENV[ADMIN_PASSWORD]}" | sha256sum | cut -c1-16)
  if [[ -n "${REC_PW[$s]:-}" && "${REC_PW[$s]}" != "$pw_hash" ]]; then
    if reconcile "The Administrator password of $s differs from .env." "It is set to ADMIN_PASSWORD from .env."; then
      pstep "Setting the Administrator password on $s" -- site-password "$s"
    fi
  fi
  if [[ "$SWITCHED" == true ]]; then pstep "Migrating $s" -- site-migrate "$s"; fi
done
pstep "Making $SITE the default site" -- use-site "$SITE"

# =============================================================================
ui_section "SeaweedFS buckets"
if [[ -n "${ENV[SEAWEEDFS_BUCKETS]:-}" ]]; then
  pstep --optional "Creating buckets: ${ENV[SEAWEEDFS_BUCKETS]}" -- buckets || ui_error "Bucket creation failed (see the log)."
else
  ui_note "No buckets configured."
  pstep --optional "Checking existing buckets" -- buckets || true
fi

# =============================================================================
ui_section "Assets"
if [[ "$DO_BUILD" == true ]]; then
  for a in frappe "${INSTALL_ORDER[@]}"; do
    pstep --optional "Building $a" -- build "$a" || {
      ui_error "Asset build of $a failed — the other apps are unaffected; fix it and run: bench build --app $a"
      FAILED_BUILDS+=("$a"); }
  done
else
  ui_note "Skipped (--no-build)."
fi

# The platform repository (./new-platform.sh) is checked out next to the bench.
if [[ -n "${ENV[PLATFORM_URL]:-}" ]]; then
  if [[ -d "$REPO_ROOT/platform/.git" ]]; then
    ui_ok "platform/ is checked out"
  else
    if ui_run --quiet-fail "Cloning the platform repository into platform/" -- git clone -q "${ENV[PLATFORM_URL]}" "$REPO_ROOT/platform"; then
      command -v pre-commit >/dev/null 2>&1 \
        && ui_run --quiet-fail "Installing the git hooks of platform/" -- bash -c "cd '$REPO_ROOT/platform' && pre-commit install" \
        || ui_warn "Git hooks of platform/ not installed (run 'just setup' in it)."
    else
      ui_error "Couldn't clone ${ENV[PLATFORM_URL]} into platform/ — continuing without it."
    fi
  fi
fi

# =============================================================================
ui_section "Extras"
if [[ "$WITH_CLAUDE" == 1 ]]; then
  vendored=""; for a in "${DEFAULT_LIST[@]}"; do vendored+="$a "; done
  pstep --optional "Claude Code CLI and bench configuration" -- claude "${vendored% }" "${CUSTOM_LIST[*]}" "${ENV[CORE_APP]:-}" \
    || ui_error "Claude Code installation failed (see the log)."
fi

workspace_render && ui_ok ".vscode/dev.code-workspace $RENDER_STATUS"
render "$TEMPLATE_DIR/vscode/settings.json.template" "$VSCODE_DIR/settings.json" --backup-dir "$BACKUP_DIR" -- \
  && ui_ok ".vscode/settings.json $RENDER_STATUS"
render "$TEMPLATE_DIR/vscode/extensions.json.template" "$VSCODE_DIR/extensions.json" --backup-dir "$BACKUP_DIR" -- \
  "EXTENSIONS_JSON=$(ext_json '        ')" && ui_ok ".vscode/extensions.json $RENDER_STATUS"
if [[ "$DO_EXTENSIONS" == true && "$VS_SOURCE" != skip && -n "$VS_COMMIT" ]]; then
  vscode_extensions "$VS_COMMIT"
fi
pstep --optional "Clearing caches" -- finalize || true

cp "$ENV_FILE" "$SNAPSHOT_FILE" && chmod 600 "$SNAPSHOT_FILE"
log_line "snapshot written: ${SNAPSHOT_FILE#"$REPO_ROOT"/}"

# =============================================================================
UI_STEP_TOTAL=0
ui_section "Ready"
(( ${#FAILED_CUSTOM[@]} )) && ui_error "Custom apps with problems: ${FAILED_CUSTOM[*]}"
(( ${#FAILED_BUILDS[@]} )) && ui_error "Apps whose assets didn't build: ${FAILED_BUILDS[*]}"
(( ${#SKIPPED_RECONCILE[@]} )) && ui_warn "${#SKIPPED_RECONCILE[@]} difference(s) between .env and the bench were left as they are (see above)."
host_ip=$(detect_lan_ip)
ui_box \
  "1. On the machine you browse from, add to its hosts file:" \
  "     ${host_ip:-<server-ip>}  $SITE $TEST_SITE $MIN_SITE" \
  "2. VS Code: Remote-SSH into this server, then" \
  "   'Dev Containers: Attach to Running Container…' › ${COMPOSE_PROJECT_NAME}-frappe-1" \
  "3. In the container: File › Open Workspace from File… › /workspace/.vscode/dev.code-workspace" \
  "4. In a container terminal:  cd /workspace/frappe-bench && bench start" \
  "5. Open http://$SITE:8000  (Administrator / ADMIN_PASSWORD from .env)" \
  "   Tests: http://$TEST_SITE:8000 (all apps) · http://$MIN_SITE:8000 (core app only)"
if cfg_meet_enabled ENV; then
  ui_note "Meet: open TCP 3000 and UDP 40000-40099 on any firewall between browsers and this host."
fi
if [[ "${ENV[MARIADB_EXPOSE_PORT]}" == 1 ]]; then
  ui_note "MariaDB: ${host_ip:-<server-ip>}:3306 (user ${ENV[MARIADB_ROOT_USERNAME]:-root}, password in .env)"
fi
exit 0
