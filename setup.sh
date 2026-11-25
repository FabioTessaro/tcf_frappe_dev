#!/usr/bin/env bash
# setup.sh — configure the project: writes .env and docker-compose.yml.
#
# Usage: ./setup.sh [options]
#
# First run: walks through every section in order —
#   1. default apps   Frappe version, which default apps (dependencies are
#                     added automatically) and the version of each, picked
#                     from the tags/branches of their git repositories
#   2. secrets        Administrator password, MariaDB root, SeaweedFS keys
#                     and, only when Meet is selected, the SFU secret/IP.
#                     Press enter at a secret prompt to generate a random one.
#   3. storage        SeaweedFS buckets to create, MariaDB host port
#   4. site           site name; the test sites are always test.<site> (all
#                     apps) and test-minimal.<site> (core app only)
#   5. custom apps    git prefix (where ./new-platform.sh and ./new-app.sh
#                     create repositories, and apps are cloned from), then
#                     the apps whose repositories already exist (none on a
#                     fresh start: ./new-app.sh adds each app it creates),
#                     optional per-app URLs, core app
# Re-run: shows the current configuration and a menu to edit single sections.
# Before saving, setup.sh lists what changed and what ./initialize.sh will
# have to do about it (and warns about anything destructive).
#
# Containers must be stopped while .env changes: if any of this project's
# containers are running, setup.sh offers to stop them (data is kept) just
# before saving.
#
# Options:
#   --answers FILE   take answers from FILE (KEY=VALUE, same keys as .env;
#                    secrets may be @generate). Missing keys are asked, or kept
#                    from the current .env on a re-run. See
#                    bootstrap/templates/answers.example.conf
#   --section NAME   re-run: edit only this section and save
#                    (apps | secrets | storage | site | custom)
#   --show           print the current configuration (secrets masked) and exit
#   -y, --yes        don't ask for the final "save?" confirmation, and stop
#                    running containers without asking
#   --trace          also write a bash execution trace into the log
#   -h, --help       show this help
#
# Log: logs/setup-<timestamp>.log
# Next step: ./initialize.sh
set -o pipefail
# shellcheck source=bootstrap/lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/apps.sh
source "$LIB_DIR/apps.sh"
# shellcheck source=bootstrap/lib/project.sh
source "$LIB_DIR/project.sh"

ANSWERS_FILE=""; ONLY_SECTION=""; SHOW_ONLY=false; ASSUME_YES=false
for a in "$@"; do [[ "$a" == -h || "$a" == --help ]] && { usage_from_header "$0"; exit 0; }; done
script_init setup "$@"
set -- "${SCRIPT_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --answers) ANSWERS_FILE="${2:-}"; shift ;;
    --answers=*) ANSWERS_FILE="${1#*=}" ;;
    --section) ONLY_SECTION="${2:-}"; shift ;;
    --section=*) ONLY_SECTION="${1#*=}" ;;
    --show) SHOW_ONLY=true ;;
    -y|--yes) ASSUME_YES=true ;;
    *) ui_die "Unknown option: $1" "See ./setup.sh --help" ;;
  esac
  shift
done
case "$ONLY_SECTION" in ""|apps|secrets|storage|site|custom) ;; *) ui_die "Unknown section '$ONLY_SECTION'." "Valid: apps secrets storage site custom" ;; esac

catalog_load

declare -A CFG=() OLD=() SNAP=() ANS=()
FIRST_RUN=true

# .env stores the Meet address twice (WEBRTC_/MEDIASOUP_); internally it is MEET_ANNOUNCED_IP.
_normalize() {
  local -n _x="$1"
  [[ -n "${_x[WEBRTC_ANNOUNCED_IP]:-}" ]] && _x[MEET_ANNOUNCED_IP]="${_x[WEBRTC_ANNOUNCED_IP]}"
  unset '_x[WEBRTC_ANNOUNCED_IP]' '_x[MEDIASOUP_ANNOUNCED_IP]'
  # APPS_MODE (shell | custom) is gone: no custom apps = CUSTOM_APPS empty.
  if [[ "${_x[APPS_MODE]:-}" == shell ]]; then _x[CUSTOM_APPS]=""; _x[CUSTOM_APP_URLS]=""; _x[CORE_APP]=""; fi
  unset '_x[APPS_MODE]'
  return 0
}
SECRET_KEYS=(ADMIN_PASSWORD MARIADB_ROOT_PASSWORD SEAWEEDFS_ACCESS_KEY SEAWEEDFS_SECRET_KEY JWT_SECRET)

if [[ -f "$ENV_FILE" ]]; then
  env_parse "$ENV_FILE" OLD; _normalize OLD
  for k in "${!OLD[@]}"; do CFG[$k]="${OLD[$k]}"; done
  for k in "${SECRET_KEYS[@]}"; do [[ -n "${OLD[$k]:-}" ]] && log_add_secret "${OLD[$k]}"; done
  # Derived from SITE_NAME (older .env files don't have it yet).
  [[ -n "${CFG[SITE_NAME]:-}" ]] && CFG[TEST_MINIMAL_SITE_NAME]="test-minimal.${CFG[SITE_NAME]}"
  FIRST_RUN=false
fi
if [[ -f "$SNAPSHOT_FILE" ]]; then env_parse "$SNAPSHOT_FILE" SNAP; _normalize SNAP; fi

# --- answers file -------------------------------------------------------------------
if [[ -n "$ANSWERS_FILE" ]]; then
  [[ -f "$ANSWERS_FILE" ]] || ui_die "Answers file not found: $ANSWERS_FILE"
  env_parse "$ANSWERS_FILE" ANS; _normalize ANS
  for k in "${SECRET_KEYS[@]}"; do [[ -n "${ANS[$k]:-}" && "${ANS[$k]}" != @generate ]] && log_add_secret "${ANS[$k]}"; done
  log_line "answers file $ANSWERS_FILE: keys ${!ANS[*]}"
  # Not asked interactively (./new-platform.sh records it), but an answers
  # file may carry it so that a new host clones the platform repository.
  if [[ -n "${ANS[PLATFORM_URL]+x}" ]]; then
    [[ -z "${ANS[PLATFORM_URL]}" ]] || valid_git_url "${ANS[PLATFORM_URL]}" \
      || ui_die "PLATFORM_URL '${ANS[PLATFORM_URL]}' is not a git URL (e.g. git@github.com:my-org/platform.git)."
    CFG[PLATFORM_URL]="${ANS[PLATFORM_URL]}"
  fi
fi
has_answer() { [[ -n "${ANS[$1]+x}" ]]; }

# need KEY WHAT — fail clearly when a value can't be asked (no terminal).
need_tty_for() {
  [[ "$UI_TTY_IN" == true ]] && return 0
  ui_die "No terminal to ask for $2 ($1)." "Add $1=… to the answers file (--answers), or run setup.sh in a terminal."
}

# =============================================================================
# Summary
# =============================================================================
show_config() {
  local a k
  ui_kv "Frappe" "${CFG[FRAPPE_VERSION]:-(not set)}"
  if [[ -n "${CFG[DEFAULT_APPS]:-}" ]]; then
    for a in ${CFG[DEFAULT_APPS]}; do k=$(app_version_key "$a"); ui_kv "  $a" "${CFG[$k]:-(no version)}"; done
  else
    ui_kv "Default apps" "none"
  fi
  ui_kv "Site" "${CFG[SITE_NAME]:-(not set)}  (developer mode: $([[ ${CFG[MAIN_SITE_DEVELOPER_MODE]:-} == 1 ]] && echo on || echo off))"
  ui_kv "Test site" "${CFG[TEST_SITE_NAME]:-(not set)}  (developer mode: on, all apps)"
  ui_kv "Minimal test site" "${CFG[TEST_MINIMAL_SITE_NAME]:-(not set)}  (developer mode: on, core app only)"
  ui_kv "Admin password" "$(cfg_mask "${CFG[ADMIN_PASSWORD]:-}")"
  ui_kv "MariaDB root" "${CFG[MARIADB_ROOT_USERNAME]:-(not set)} / $(cfg_mask "${CFG[MARIADB_ROOT_PASSWORD]:-}")"
  ui_kv "MariaDB host port" "$([[ ${CFG[MARIADB_EXPOSE_PORT]:-} == 1 ]] && echo "published (3306)" || echo "${CFG[MARIADB_EXPOSE_PORT]:+not published}")"
  ui_kv "SeaweedFS keys" "$(cfg_mask "${CFG[SEAWEEDFS_ACCESS_KEY]:-}") / $(cfg_mask "${CFG[SEAWEEDFS_SECRET_KEY]:-}")"
  ui_kv "Buckets" "${CFG[SEAWEEDFS_BUCKETS]:-none}"
  if cfg_meet_enabled CFG; then
    ui_kv "Meet SFU secret" "$(cfg_mask "${CFG[JWT_SECRET]:-}")"
    ui_kv "Meet announced IP" "${CFG[MEET_ANNOUNCED_IP]:-(not set)}"
  fi
  ui_kv "Git prefix" "${CFG[CUSTOM_APPS_GIT_PREFIX]:-(not set)}"
  if [[ -n "${CFG[CUSTOM_APPS]:-}" ]]; then
    ui_kv "Custom apps" "${CFG[CUSTOM_APPS]}  (core: ${CFG[CORE_APP]:-?})"
    for a in ${CFG[CUSTOM_APPS]}; do ui_kv "  $a" "$(cfg_custom_url CFG "$a")"; done
  else
    ui_kv "Custom apps" "none yet (./new-app.sh creates them)"
  fi
  ui_kv "Platform repository" "${CFG[PLATFORM_URL]:-(none yet: ./new-platform.sh)}"
}

if [[ "$SHOW_ONLY" == true ]]; then
  SCRIPT_SUMMARY=false
  [[ "$FIRST_RUN" == true ]] && ui_die "No .env yet — run ./setup.sh to create it."
  ui_banner "frappe-dev · setup" "current configuration"
  show_config
  exit 0
fi

ui_banner "frappe-dev · setup" "$([[ $FIRST_RUN == true ]] && echo "new configuration" || echo "edit configuration")"

# =============================================================================
# Running containers
# =============================================================================
ensure_stopped() {
  docker_detect
  if [[ "$DOCKER_STATUS" != 0 ]]; then log_line "docker not reachable — nothing can be running"; return 0; fi
  local running; running=$(project_running_services | paste -sd' ')
  [[ -z "$running" ]] && { ui_ok "No project containers are running"; return 0; }
  ui_warn "Project containers are running: $running"
  ui_note "They read .env when they start, so they must be stopped before it changes."
  ui_note "Stopping keeps containers, volumes and data; ./initialize.sh starts them again."
  if [[ "$ASSUME_YES" != true ]]; then
    need_tty_for "stop" "permission to stop the running containers"
    ui_select "Stop them now?" "stop::Stop the containers and continue" "abort::Leave them running and exit (nothing is changed)" || exit 1
    [[ "$UI_VALUE" == abort ]] && { ui_info "Nothing changed."; exit 0; }
  fi
  if [[ -f "$COMPOSE_FILE" ]]; then
    ui_run "Stopping the project containers" -- dc stop || ui_die "Couldn't stop the containers."
  else
    # shellcheck disable=SC2046
    ui_run "Stopping the project containers" -- dk stop $(project_containers --running) || ui_die "Couldn't stop the containers."
  fi
}

# =============================================================================
# Section 1 — default apps
# =============================================================================
section_apps() {
  ui_section "Default apps and versions"
  local url="${CAT_REPO[frappe]}" a k

  if has_answer FRAPPE_VERSION; then
    CFG[FRAPPE_VERSION]="${ANS[FRAPPE_VERSION]}"
    _verify_ref frappe "$url" "${CFG[FRAPPE_VERSION]}"
  elif [[ -n "$ANSWERS_FILE" && -n "${CFG[FRAPPE_VERSION]:-}" ]]; then :
  else
    need_tty_for FRAPPE_VERSION "the Frappe version"
    pick_version "frappe" "$url" "${CFG[FRAPPE_VERSION]:-}" || exit 1
    CFG[FRAPPE_VERSION]="$UI_VALUE"
  fi
  ui_ok "Frappe ${CFG[FRAPPE_VERSION]}"
  local fmajor; fmajor=$(version_major "${CFG[FRAPPE_VERSION]}")

  local selected
  if has_answer DEFAULT_APPS; then
    selected="${ANS[DEFAULT_APPS]}"
    for a in $selected; do [[ -n "${CAT_REPO[$a]:-}" && "$a" != frappe ]] || ui_die "DEFAULT_APPS: '$a' is not in bootstrap/templates/apps.catalog"; done
  elif [[ -n "$ANSWERS_FILE" && -n "${CFG[DEFAULT_APPS]+x}" ]]; then
    selected="${CFG[DEFAULT_APPS]}"
  else
    need_tty_for DEFAULT_APPS "the default apps"
    local items=() deps
    while IFS= read -r a; do
      deps="${CAT_DEPS[$a]}"; deps="${deps:+ (needs ${deps//,/, })}"
      items+=("$a::$a::${CAT_DESC[$a]}$deps")
    done < <(catalog_optional)
    ui_checklist --on "${CFG[DEFAULT_APPS]:-}" "Which default apps should be installed?" "${items[@]}" || exit 1
    selected="${UI_SELECTED[*]}"
  fi
  apps_resolve "$selected"
  for a in "${APPS_ADDED[@]}"; do
    ui_info "Added $a: required by $(apps_dependents "$a" "${APPS_RESOLVED[*]}")"
  done
  CFG[DEFAULT_APPS]="${APPS_RESOLVED[*]}"

  # Versions of the selected apps; forget the others.
  for a in "${CAT_NAMES[@]}"; do
    [[ "$a" == frappe ]] && continue
    k=$(app_version_key "$a")
    if ! contains "$a" "${APPS_RESOLVED[@]}"; then unset "CFG[$k]"; continue; fi
    local hint=""; app_has_feature "$a" follows-frappe && hint="$fmajor"
    if has_answer "$k"; then
      CFG[$k]="${ANS[$k]}"; _verify_ref "$a" "${CAT_REPO[$a]}" "${CFG[$k]}"
    elif [[ -n "$ANSWERS_FILE" && -n "${CFG[$k]:-}" ]]; then :
    else
      need_tty_for "$k" "the $a version"
      pick_version "$a" "${CAT_REPO[$a]}" "${CFG[$k]:-}" "$hint" || exit 1
      CFG[$k]="$UI_VALUE"
    fi
    if [[ -n "$hint" ]]; then
      local amajor; amajor=$(version_major "${CFG[$k]}")
      if [[ -n "$amajor" && "$amajor" != "$fmajor" ]]; then
        ui_warn "$a ${CFG[$k]} is for Frappe v$amajor but Frappe is ${CFG[FRAPPE_VERSION]} — installation will probably fail."
      fi
    fi
    ui_ok "$a ${CFG[$k]}"
  done
  [[ ${#APPS_RESOLVED[@]} -eq 0 ]] && ui_ok "No default apps besides Frappe"
  return 0
}

_verify_ref() {
  local rc=0
  git_ref_exists "$2" "$3" || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) ui_die "$1: '$3' is not a tag or branch of $2." ;;
    *) ui_warn "$1: couldn't reach $2 to verify '$3' — using it unverified." ;;
  esac
}

# =============================================================================
# Section 2 — secrets
# =============================================================================
# _secret KEY LABEL MODE — MODE: ask (prompt) | keep-or-ask
_secret() {
  local key="$1" label="$2"
  if has_answer "$key"; then
    if [[ "${ANS[$key]}" == @generate && -n "${CFG[$key]:-}" ]]; then
      ui_ok "$label: kept (already generated)"; return 0
    elif [[ "${ANS[$key]}" == @generate ]]; then CFG[$key]="$(gen_password)"; log_add_secret "${CFG[$key]}"
    else valid_secret "${ANS[$key]}" || ui_die "$key in the answers file can't contain a single quote (') or a line break."
      CFG[$key]="${ANS[$key]}"
      local weakness; weakness="$(secret_weakness "${ANS[$key]}")"
      [[ -n "$weakness" ]] && ui_warn "$key: $weakness"
    fi
    ui_ok "$label: from the answers file"; return 0
  fi
  if [[ -n "$ANSWERS_FILE" && -n "${CFG[$key]:-}" ]]; then return 0; fi
  need_tty_for "$key" "$label"
  ui_secret --generate gen_password --validate valid_secret --weak secret_weakness \
    --error "a single quote (') or line break can't be stored in .env" "$label"
  CFG[$key]="$UI_VALUE"
}

section_secrets() {
  ui_section "Secrets"
  local meet=false; cfg_meet_enabled CFG && meet=true
  local -a all=(
    "ADMIN_PASSWORD::Administrator password (all three sites)"
    "MARIADB_ROOT_USERNAME::MariaDB root user name"
    "MARIADB_ROOT_PASSWORD::MariaDB root password"
    "SEAWEEDFS_ACCESS_KEY::SeaweedFS S3 access key"
    "SEAWEEDFS_SECRET_KEY::SeaweedFS S3 secret key"
  )
  if [[ "$meet" == true ]]; then
    all+=("JWT_SECRET::Meet SFU shared secret (JWT)" "MEET_ANNOUNCED_IP::Meet SFU address announced to browsers")
  else
    unset 'CFG[JWT_SECRET]' 'CFG[MEET_ANNOUNCED_IP]'
  fi

  # Which ones to (re)ask: everything missing, plus — on a re-run — those the user picks.
  local -a todo=() present=() it key
  for it in "${all[@]}"; do
    key="${it%%::*}"
    if [[ -z "${CFG[$key]:-}" ]] || has_answer "$key"; then todo+=("$key"); else present+=("$it"); fi
  done
  if (( ${#present[@]} )) && [[ -z "$ANSWERS_FILE" ]] && [[ "${1:-}" != missing-only ]]; then
    ui_checklist "Which of the current values do you want to change?" "${present[@]}" || exit 1
    todo+=("${UI_SELECTED[@]}")
  fi

  for it in "${all[@]}"; do
    key="${it%%::*}"
    contains "$key" "${todo[@]}" || continue
    case "$key" in
      MARIADB_ROOT_USERNAME)
        if has_answer "$key"; then
          _valid_dbuser "${ANS[$key]}" || ui_die "MARIADB_ROOT_USERNAME '${ANS[$key]}': use 1-32 letters, digits and _ only."
          CFG[$key]="${ANS[$key]}"
        else
          need_tty_for "$key" "the MariaDB root user name"
          ui_input --default "${CFG[$key]:-root}" --validate _valid_dbuser --error "letters, digits and _ only" "MariaDB root user name"
          CFG[$key]="$UI_VALUE"
        fi
        [[ "${CFG[$key]}" != root ]] && ui_warn "The MariaDB image only creates the 'root' account; '${CFG[$key]}' must exist in MariaDB or bench can't create sites."
        ;;
      MEET_ANNOUNCED_IP)
        if has_answer "$key"; then
          valid_ip_or_host "${ANS[$key]}" || ui_die "MEET_ANNOUNCED_IP: '${ANS[$key]}' is not an IP address or host name."
          CFG[$key]="${ANS[$key]}"
        else
          need_tty_for "$key" "the Meet announced address"
          local lan; lan=$(detect_lan_ip)
          ui_note "The address browsers use to reach this host's UDP ports 40000-40099 (detected LAN IP: ${lan:-none})."
          ui_input --default "${CFG[$key]:-$lan}" --validate valid_ip_or_host --error "enter an IP address or a host name" "Meet SFU announced address"
          CFG[$key]="$UI_VALUE"
        fi ;;
      *) _secret "$key" "${it#*::}" ;;
    esac
  done
  ui_ok "Secrets complete"
}
_valid_dbuser() { [[ "$1" =~ ^[A-Za-z0-9_]{1,32}$ ]]; }

# =============================================================================
# Section 3 — storage & services
# =============================================================================
section_storage() {
  ui_section "Storage and services"
  local b
  if has_answer SEAWEEDFS_BUCKETS; then
    for b in ${ANS[SEAWEEDFS_BUCKETS]}; do valid_bucket "$b" || ui_die "SEAWEEDFS_BUCKETS: invalid bucket name '$b'"; done
    CFG[SEAWEEDFS_BUCKETS]="${ANS[SEAWEEDFS_BUCKETS]}"
  elif [[ -n "$ANSWERS_FILE" && -n "${CFG[SEAWEEDFS_BUCKETS]+x}" ]]; then :
  else
    need_tty_for SEAWEEDFS_BUCKETS "the SeaweedFS buckets"
    local -a names=() items=() suggested=()
    while IFS= read -r b || [[ -n "$b" ]]; do
      b="${b%%#*}"; b="${b//[[:space:]]/}"; [[ -z "$b" ]] && continue
      suggested+=("$b"); contains "$b" "${names[@]}" || names+=("$b")
    done < "$TEMPLATE_DIR/buckets.list"
    for b in ${CFG[SEAWEEDFS_BUCKETS]:-}; do contains "$b" "${names[@]}" || names+=("$b"); done
    for b in "${names[@]}"; do
      if contains "$b" "${suggested[@]}"; then items+=("$b::$b::suggested"); else items+=("$b::$b::current"); fi
    done
    local preset="${CFG[SEAWEEDFS_BUCKETS]-${suggested[*]}}"
    if (( ${#items[@]} )); then
      ui_checklist --on "$preset" "Which SeaweedFS buckets should be created?" "${items[@]}" || exit 1
      names=("${UI_SELECTED[@]}")
    else
      names=()
    fi
    while true; do
      ui_input --allow-empty --validate valid_bucket \
        --error "3-63 characters: lowercase letters, digits, dots and dashes" "Add another bucket (enter to finish)"
      [[ -z "$UI_VALUE" ]] && break
      if contains "$UI_VALUE" "${names[@]}"; then ui_note "$UI_VALUE is already in the list"; else names+=("$UI_VALUE"); fi
    done
    CFG[SEAWEEDFS_BUCKETS]="${names[*]}"
  fi
  ui_ok "Buckets: ${CFG[SEAWEEDFS_BUCKETS]:-none}"

  if has_answer MARIADB_EXPOSE_PORT; then
    [[ "${ANS[MARIADB_EXPOSE_PORT]}" =~ ^[01]$ ]] || ui_die "MARIADB_EXPOSE_PORT must be 1 or 0."
    CFG[MARIADB_EXPOSE_PORT]="${ANS[MARIADB_EXPOSE_PORT]}"
  elif [[ -n "$ANSWERS_FILE" && -n "${CFG[MARIADB_EXPOSE_PORT]:-}" ]]; then :
  else
    need_tty_for MARIADB_EXPOSE_PORT "whether to publish the MariaDB port"
    ui_select --initial "${CFG[MARIADB_EXPOSE_PORT]:-}" "Publish MariaDB on this host's port 3306 (for DBeaver & co.)?" \
      "1::Yes — reachable on <host>:3306" "0::No — only reachable from the containers" || exit 1
    CFG[MARIADB_EXPOSE_PORT]="$UI_VALUE"
  fi
  ui_ok "MariaDB port 3306 $([[ ${CFG[MARIADB_EXPOSE_PORT]} == 1 ]] && echo "published" || echo "not published")"
}

# =============================================================================
# Section 4 — site
# =============================================================================
section_site() {
  ui_section "Site"
  if has_answer SITE_NAME; then
    valid_site_name "${ANS[SITE_NAME]}" || ui_die "SITE_NAME '${ANS[SITE_NAME]}' is not a valid lowercase host name (and must not start with test. or test-minimal.)."
    CFG[SITE_NAME]="${ANS[SITE_NAME]}"
  elif [[ -n "$ANSWERS_FILE" && -n "${CFG[SITE_NAME]:-}" ]]; then :
  else
    need_tty_for SITE_NAME "the site name"
    ui_note "The host name you'll open in the browser (e.g. erp.local); add it to your hosts file later."
    ui_input --default "${CFG[SITE_NAME]:-}" --validate valid_site_name \
      --error "use a lowercase host name like erp.local (not starting with test. or test-minimal.)" "Site name"
    CFG[SITE_NAME]="$UI_VALUE"
  fi
  CFG[TEST_SITE_NAME]="test.${CFG[SITE_NAME]}"
  CFG[TEST_MINIMAL_SITE_NAME]="test-minimal.${CFG[SITE_NAME]}"
  ui_ok "Site ${CFG[SITE_NAME]} · test sites ${CFG[TEST_SITE_NAME]} (all apps) and ${CFG[TEST_MINIMAL_SITE_NAME]} (core app only)"

  if has_answer MAIN_SITE_DEVELOPER_MODE; then
    [[ "${ANS[MAIN_SITE_DEVELOPER_MODE]}" =~ ^[01]$ ]] || ui_die "MAIN_SITE_DEVELOPER_MODE must be 1 or 0."
    CFG[MAIN_SITE_DEVELOPER_MODE]="${ANS[MAIN_SITE_DEVELOPER_MODE]}"
  elif [[ -n "$ANSWERS_FILE" && -n "${CFG[MAIN_SITE_DEVELOPER_MODE]:-}" ]]; then :
  else
    need_tty_for MAIN_SITE_DEVELOPER_MODE "developer mode on the main site"
    ui_select --initial "${CFG[MAIN_SITE_DEVELOPER_MODE]:-}" \
      "Developer mode on the main site ${CFG[SITE_NAME]}? (the test site always has it)" \
      "1::Yes — developer mode on" "0::No — developer mode off" || exit 1
    CFG[MAIN_SITE_DEVELOPER_MODE]="$UI_VALUE"
  fi
  ui_ok "Main site developer mode: $([[ ${CFG[MAIN_SITE_DEVELOPER_MODE]} == 1 ]] && echo on || echo off)"
}

# =============================================================================
# Section 5 — custom apps
# =============================================================================
_url_override_set() {
  # _url_override_set APP URL|"" — update CFG[CUSTOM_APP_URLS]
  local app="$1" url="$2" pair out=()
  for pair in ${CFG[CUSTOM_APP_URLS]:-}; do [[ "${pair%%=*}" == "$app" ]] || out+=("$pair"); done
  [[ -n "$url" ]] && out+=("$app=$url")
  CFG[CUSTOM_APP_URLS]="${out[*]}"
}

_check_repo() {
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
    timeout 60 git ls-remote --heads "$1"
}

section_custom() {
  ui_section "Custom apps"
  # Answers files written for older versions: APPS_MODE=shell means no apps.
  if [[ "${ANS[APPS_MODE]:-}" == shell ]] && ! has_answer CUSTOM_APPS; then ANS[CUSTOM_APPS]=""; fi

  # Git prefix: always needed — new-platform.sh and new-app.sh create their
  # repositories under it, initialize.sh clones the apps from it.
  if has_answer CUSTOM_APPS_GIT_PREFIX; then
    valid_git_prefix "${ANS[CUSTOM_APPS_GIT_PREFIX]}" || ui_die "CUSTOM_APPS_GIT_PREFIX '${ANS[CUSTOM_APPS_GIT_PREFIX]}' is not a git URL prefix (e.g. git@github.com:my-org)."
    CFG[CUSTOM_APPS_GIT_PREFIX]="${ANS[CUSTOM_APPS_GIT_PREFIX]}"
  elif [[ -n "$ANSWERS_FILE" && -n "${CFG[CUSTOM_APPS_GIT_PREFIX]:-}" ]]; then :
  else
    need_tty_for CUSTOM_APPS_GIT_PREFIX "the git prefix"
    local def="${CFG[CUSTOM_APPS_GIT_PREFIX]:-}" login=""
    if [[ -z "$def" ]] && command -v gh >/dev/null 2>&1; then
      login=$(timeout 15 gh api user --jq .login 2>/dev/null) && [[ -n "$login" ]] && def="git@github.com:$login"
    fi
    ui_note "Where your repositories live: ./new-platform.sh and ./new-app.sh create them there,"
    ui_note "and apps are cloned from <prefix>/<app>.git. E.g. git@github.com:my-org (no trailing slash)."
    ui_input --default "$def" --validate valid_git_prefix \
      --error "expected something like git@github.com:my-org or https://github.com/my-org" "Git prefix"
    CFG[CUSTOM_APPS_GIT_PREFIX]="$UI_VALUE"
  fi

  # App names: only apps whose repositories already exist. New apps are
  # created by ./new-app.sh, which adds them to CUSTOM_APPS itself.
  local -a apps=() a
  if has_answer CUSTOM_APPS; then
    for a in ${ANS[CUSTOM_APPS]}; do valid_app_name "$a" || ui_die "CUSTOM_APPS: invalid app name '$a'"; apps+=("$a"); done
    has_answer CUSTOM_APP_URLS && CFG[CUSTOM_APP_URLS]="${ANS[CUSTOM_APP_URLS]}"
  elif [[ -n "$ANSWERS_FILE" ]]; then
    read -r -a apps <<< "${CFG[CUSTOM_APPS]:-}"
  else
    need_tty_for CUSTOM_APPS "the custom app names"
    read -r -a apps <<< "${CFG[CUSTOM_APPS]:-}"
    (( ${#apps[@]} )) || ui_note "New apps: leave this empty and create them later with ./new-app.sh (it adds them here). List only apps whose repositories already exist."
    while true; do
      if (( ${#apps[@]} )); then
        ui_info "Custom apps: ${apps[*]}"
        local items=("done::Done" "add::Add an app…")
        (( ${#apps[@]} )) && items+=("remove::Remove an app…")
        ui_select "Custom apps" "${items[@]}" || exit 1
        case "$UI_VALUE" in
          done) break ;;
          remove)
            local r=(); for a in "${apps[@]}"; do r+=("$a::$a"); done
            ui_select "Remove which app?" "${r[@]}" || continue
            local keep=(); for a in "${apps[@]}"; do [[ "$a" == "$UI_VALUE" ]] || keep+=("$a"); done
            _url_override_set "$UI_VALUE" ""
            apps=("${keep[@]}"); continue ;;
        esac
      fi
      ui_input --allow-empty --validate valid_app_name \
        --error "app names: lowercase letters, digits and _, starting with a letter" \
        "Existing custom app name (enter to finish$( (( ${#apps[@]} )) || echo ": none yet"))"
      [[ -z "$UI_VALUE" ]] && break
      if contains "$UI_VALUE" "${apps[@]}" || contains "$UI_VALUE" "${CAT_NAMES[@]}"; then
        ui_note "$UI_VALUE is already used"; continue
      fi
      apps+=("$UI_VALUE")
      local new="$UI_VALUE" def="${CFG[CUSTOM_APPS_GIT_PREFIX]}/$UI_VALUE.git"
      ui_select "Git URL for $new" "prefix::$def" "custom::A different URL…" || exit 1
      if [[ "$UI_VALUE" == custom ]]; then
        ui_input --validate valid_git_url --error "expected git@host:path.git or https://… / ssh://…" "Git URL for $new"
        _url_override_set "$new" "$UI_VALUE"
      else
        _url_override_set "$new" ""
      fi
    done
  fi

  if (( ${#apps[@]} == 0 )); then
    CFG[CUSTOM_APPS]=""; CFG[CUSTOM_APP_URLS]=""; CFG[CORE_APP]=""
    ui_ok "No custom apps yet — ./new-app.sh creates them under ${CFG[CUSTOM_APPS_GIT_PREFIX]}"
    return 0
  fi

  # Reachability of every repository (with the same SSH key the container uses).
  for a in "${apps[@]}"; do
    local url; url=$(cfg_custom_url CFG "$a")
    while ! ui_run --quiet-fail "Checking access to $url" -- _check_repo "$url"; do
      if [[ "$UI_TTY_IN" != true || -n "$ANSWERS_FILE" ]]; then
        ui_warn "Can't reach $url (wrong URL, or the SSH key isn't authorized) — initialize.sh will fail to clone $a."
        break
      fi
      ui_select "Can't reach $url" "retry::Try again" "url::Use a different URL for $a…" "keep::Keep it anyway" || exit 1
      case "$UI_VALUE" in
        keep) ui_warn "$a: $url not verified."; break ;;
        url)
          ui_input --validate valid_git_url --error "expected git@host:path.git or https://… / ssh://…" "Git URL for $a"
          _url_override_set "$a" "$UI_VALUE"; url="$UI_VALUE" ;;
      esac
    done
  done

  # Core app
  local core=""
  if has_answer CORE_APP; then
    core="${ANS[CORE_APP]}"
    contains "$core" "${apps[@]}" || ui_die "CORE_APP '$core' is not one of CUSTOM_APPS (${apps[*]})."
  elif [[ -n "$ANSWERS_FILE" && -n "${CFG[CORE_APP]:-}" ]] && contains "${CFG[CORE_APP]}" "${apps[@]}"; then
    core="${CFG[CORE_APP]}"
  else
    need_tty_for CORE_APP "the core app"
    local items=(); for a in "${apps[@]}"; do items+=("$a::$a"); done
    ui_select --initial "${CFG[CORE_APP]:-}" "Which one is the core app (Vue portal shell, installed first)?" "${items[@]}" || exit 1
    core="$UI_VALUE"
  fi
  local ordered=("$core"); for a in "${apps[@]}"; do [[ "$a" != "$core" ]] && ordered+=("$a"); done
  # Drop URL overrides of apps no longer listed.
  local pair kept=()
  for pair in ${CFG[CUSTOM_APP_URLS]:-}; do contains "${pair%%=*}" "${ordered[@]}" && kept+=("$pair"); done
  CFG[CUSTOM_APP_URLS]="${kept[*]}"
  CFG[CUSTOM_APPS]="${ordered[*]}"
  CFG[CORE_APP]="$core"
  ui_ok "Custom apps: ${CFG[CUSTOM_APPS]} (core: $core)"
}

# =============================================================================
# Completeness, review and save
# =============================================================================
cfg_missing() {
  MISSING=()
  local k a
  for k in FRAPPE_VERSION SITE_NAME MAIN_SITE_DEVELOPER_MODE ADMIN_PASSWORD MARIADB_ROOT_USERNAME \
           MARIADB_ROOT_PASSWORD MARIADB_EXPOSE_PORT SEAWEEDFS_ACCESS_KEY SEAWEEDFS_SECRET_KEY CUSTOM_APPS_GIT_PREFIX; do
    [[ -n "${CFG[$k]:-}" ]] || MISSING+=("$k")
  done
  [[ -n "${CFG[SEAWEEDFS_BUCKETS]+x}" ]] || MISSING+=(SEAWEEDFS_BUCKETS)
  [[ -n "${CFG[DEFAULT_APPS]+x}" ]] || MISSING+=(DEFAULT_APPS)
  for a in ${CFG[DEFAULT_APPS]:-}; do k=$(app_version_key "$a"); [[ -n "${CFG[$k]:-}" ]] || MISSING+=("$k"); done
  if cfg_meet_enabled CFG; then
    [[ -n "${CFG[JWT_SECRET]:-}" ]] || MISSING+=(JWT_SECRET)
    [[ -n "${CFG[MEET_ANNOUNCED_IP]:-}" ]] || MISSING+=(MEET_ANNOUNCED_IP)
  fi
  if [[ -n "${CFG[CUSTOM_APPS]:-}" ]]; then
    [[ -n "${CFG[CORE_APP]:-}" ]] || MISSING+=(CORE_APP)
  fi
}

# Ask the sections that own missing values (e.g. Meet secrets after adding Meet).
complete_missing() {
  cfg_missing
  (( ${#MISSING[@]} == 0 )) && return 0
  log_line "missing values: ${MISSING[*]}"
  local m
  for m in "${MISSING[@]}"; do
    case "$m" in
      FRAPPE_VERSION|DEFAULT_APPS|*_VERSION) section_apps; break ;;
    esac
  done
  cfg_missing
  for m in "${MISSING[@]}"; do
    case "$m" in ADMIN_PASSWORD|MARIADB_*|SEAWEEDFS_ACCESS_KEY|SEAWEEDFS_SECRET_KEY|JWT_SECRET|MEET_ANNOUNCED_IP)
      [[ "$m" == MARIADB_EXPOSE_PORT ]] && continue; section_secrets missing-only; break ;; esac
  done
  cfg_missing
  for m in "${MISSING[@]}"; do case "$m" in SEAWEEDFS_BUCKETS|MARIADB_EXPOSE_PORT) section_storage; break ;; esac; done
  cfg_missing
  for m in "${MISSING[@]}"; do case "$m" in SITE_NAME|MAIN_SITE_DEVELOPER_MODE) section_site; break ;; esac; done
  cfg_missing
  for m in "${MISSING[@]}"; do case "$m" in CUSTOM_*|CORE_APP) section_custom; break ;; esac; done
  cfg_missing
  (( ${#MISSING[@]} == 0 )) || ui_die "Still missing: ${MISSING[*]}"
}

review_and_save() {
  UI_STEP_TOTAL=0
  ui_section "Review"
  show_config

  # Changes compared with the current .env
  if [[ "$FIRST_RUN" == false ]]; then
    local k changed=() all_keys
    all_keys=$(printf '%s\n' "${!OLD[@]}" "${!CFG[@]}" | sort -u)
    while IFS= read -r k; do
      [[ -z "$k" || "$k" == MARIADB_AUTO_UPGRADE || "$k" == SEAWEEDFS_ENDPOINT || "$k" == CLAMAV_* ]] && continue
      [[ "${OLD[$k]:-}" == "${CFG[$k]:-}" ]] && continue
      changed+=("$k")
    done <<< "$all_keys"
    if (( ${#changed[@]} == 0 )); then
      ui_ok "No changes compared with the current .env"
      compose_render CFG --check >/dev/null
      if [[ $? -eq 0 ]]; then ui_info "docker-compose.yml is up to date too — nothing to save."; return 0; fi
    else
      ui_info "Changed: ${changed[*]}"
    fi
  fi

  # What initialize.sh will have to do, relative to what is actually deployed.
  if (( ${#SNAP[@]} )); then
    cfg_impact SNAP CFG
    if [[ "$IMPACT_LEVEL" == none ]]; then
      ui_ok "Matches the last initialized configuration — nothing for initialize.sh to change."
    else
      ui_info "Compared with the last ./initialize.sh run:"
      cfg_print_impact
      case "$IMPACT_LEVEL" in
        rerun) ui_info "Run ./initialize.sh to apply these changes." ;;
        reconcile) ui_warn "Run ./initialize.sh: it will ask before changing or removing existing apps, sites or passwords." ;;
        rebuild) ui_warn "Some changes can't be applied in place: initialize.sh will offer a rebuild (data loss) — read the lines above carefully." ;;
      esac
    fi
  elif [[ -d "$BENCH_DIR" ]]; then
    ui_warn "frappe-bench/ exists but was never initialized by these scripts — initialize.sh will reconcile it with this configuration."
  fi
  check_platform_frappe

  if [[ "$ASSUME_YES" != true ]]; then
    need_tty_for "--yes" "the final confirmation"
    ui_confirm "Save the configuration?" || { ui_info "Nothing saved."; exit 0; }
  fi
  ensure_stopped
  write_files
}

# check_platform_frappe — warn when the Frappe major version differs from the
# one platform.lock pins. Minor and patch may differ: the development
# environment follows the latest release (ADR 0001), CI uses the lock.
check_platform_frappe() {
  local lock="$REPO_ROOT/platform/platform.lock" locked lmajor emajor
  [[ -f "$lock" ]] || return 0
  locked=$(awk '/^\[/ {s = ($0 == "[frappe]")} s && /^version[[:space:]]*=/ {gsub(/.*=[[:space:]]*"|".*/, ""); print; exit}' "$lock")
  [[ -n "$locked" ]] || return 0
  lmajor=$(version_major "$locked"); emajor=$(version_major "${CFG[FRAPPE_VERSION]:-}")
  [[ -n "$lmajor" && -n "$emajor" && "$lmajor" != "$emajor" ]] || return 0
  ui_warn "Frappe ${CFG[FRAPPE_VERSION]} is major v$emajor, but platform/platform.lock pins $locked (v$lmajor)."
  ui_note "Apps developed here would be tested by CI on another Frappe major version."
}

write_files() {
  local a k versions="" meet=0
  for a in ${CFG[DEFAULT_APPS]:-}; do
    k=$(app_version_key "$a"); versions+="$k=$(env_quote "${CFG[$k]}")"$'\n'
  done
  versions="${versions%$'\n'}"
  cfg_meet_enabled CFG && meet=1
  CFG[TEST_MINIMAL_SITE_NAME]="test-minimal.${CFG[SITE_NAME]}"
  render "$TEMPLATE_DIR/env.template" "$ENV_FILE" --mode 600 --backup-dir "$BACKUP_DIR" -- \
    "GENERATED_AT=$(date '+%Y-%m-%d %H:%M')" \
    "SITE_NAME=$(env_quote "${CFG[SITE_NAME]}")" \
    "TEST_SITE_NAME=$(env_quote "${CFG[TEST_SITE_NAME]}")" \
    "TEST_MINIMAL_SITE_NAME=$(env_quote "${CFG[TEST_MINIMAL_SITE_NAME]}")" \
    "MAIN_SITE_DEVELOPER_MODE=$(env_quote "${CFG[MAIN_SITE_DEVELOPER_MODE]}")" \
    "ADMIN_PASSWORD=$(env_quote "${CFG[ADMIN_PASSWORD]}")" \
    "MARIADB_ROOT_USERNAME=$(env_quote "${CFG[MARIADB_ROOT_USERNAME]}")" \
    "MARIADB_ROOT_PASSWORD=$(env_quote "${CFG[MARIADB_ROOT_PASSWORD]}")" \
    "MARIADB_EXPOSE_PORT=$(env_quote "${CFG[MARIADB_EXPOSE_PORT]}")" \
    "SEAWEEDFS_ACCESS_KEY=$(env_quote "${CFG[SEAWEEDFS_ACCESS_KEY]}")" \
    "SEAWEEDFS_SECRET_KEY=$(env_quote "${CFG[SEAWEEDFS_SECRET_KEY]}")" \
    "SEAWEEDFS_BUCKETS=$(env_quote "${CFG[SEAWEEDFS_BUCKETS]:-}")" \
    "FRAPPE_VERSION=$(env_quote "${CFG[FRAPPE_VERSION]}")" \
    "DEFAULT_APPS=$(env_quote "${CFG[DEFAULT_APPS]:-}")" \
    "APP_VERSIONS=$versions" \
    "MEET_ENABLED=$meet" \
    "JWT_SECRET=$(env_quote "${CFG[JWT_SECRET]:-}")" \
    "MEET_ANNOUNCED_IP=$(env_quote "${CFG[MEET_ANNOUNCED_IP]:-}")" \
    "CUSTOM_APPS_GIT_PREFIX=$(env_quote "${CFG[CUSTOM_APPS_GIT_PREFIX]:-}")" \
    "CUSTOM_APPS=$(env_quote "${CFG[CUSTOM_APPS]:-}")" \
    "CUSTOM_APP_URLS=$(env_quote "${CFG[CUSTOM_APP_URLS]:-}")" \
    "CORE_APP=$(env_quote "${CFG[CORE_APP]:-}")" \
    "PLATFORM_URL=$(env_quote "${CFG[PLATFORM_URL]:-}")" \
    || ui_die "Writing .env failed."
  ui_ok ".env $RENDER_STATUS (mode 600$([[ $RENDER_STATUS == updated ]] && echo ", previous version in .state/backups/"))"
  compose_render CFG || ui_die "Writing docker-compose.yml failed."
  ui_ok "docker-compose.yml $RENDER_STATUS"
}

# =============================================================================
# Main
# =============================================================================
# Running containers are only stopped right before saving (review_and_save).
if [[ "$FIRST_RUN" == true ]]; then
  UI_STEP_TOTAL=5
  [[ -n "$ONLY_SECTION" ]] && ui_die "--section needs an existing .env (this is the first run)."
  section_apps
  section_secrets
  section_storage
  section_site
  section_custom
elif [[ -n "$ANSWERS_FILE" ]]; then
  # Re-run with answers: apply the provided keys, keep everything else.
  section_apps; section_secrets; section_storage; section_site; section_custom
elif [[ -n "$ONLY_SECTION" ]]; then
  "section_$ONLY_SECTION"
else
  ui_section "Current configuration"
  show_config
  while true; do
    UI_STEP_NO=0
    printf '\n'
    ui_select "What do you want to change?" \
      "apps::Default apps and versions" \
      "secrets::Secrets" \
      "storage::Storage and services (buckets, MariaDB port)" \
      "site::Site name and developer mode" \
      "custom::Custom apps (git prefix, existing apps, core app)" \
      "=save::Review and save" \
      "=quit::Quit without saving" || exit 1
    case "$UI_VALUE" in
      =save) break ;;
      =quit) ui_info "Nothing saved."; exit 0 ;;
      *) "section_$UI_VALUE" ;;
    esac
  done
fi

complete_missing
review_and_save

UI_STEP_TOTAL=0
ui_section "Next steps"
n=1
ui_info "$n. Build and start everything:          ./initialize.sh"; n=$((n + 1))
if [[ -z "${CFG[PLATFORM_URL]:-}" ]]; then
  ui_info "$n. Create the platform repository:      ./new-platform.sh"; n=$((n + 1))
fi
if [[ -x "$REPO_ROOT/new-app.sh" ]]; then
  if [[ -z "${CFG[CUSTOM_APPS]:-}" ]]; then
    ui_info "$n. Create the core app, then the others: ./new-app.sh"
  else
    ui_info "$n. Create more apps when needed:         ./new-app.sh"
  fi
fi
