#!/usr/bin/env bash
# shellcheck disable=SC2034
# -----------------------------------------------------------------------------
# bootstrap/lib/project.sh — project-level helpers built on the .env values.
# -----------------------------------------------------------------------------
# Every function takes the NAME of an associative array holding .env values
# (ENV after env_require, or setup.sh's in-progress CFG).
#
# cfg_meet_enabled ARR            0 when an app with the "sfu" feature is selected
# cfg_custom_url ARR APP          git URL of a custom app
# compose_render ARR [--check]    docker-compose.yml from its template
# cfg_impact OLD NEW              what ./initialize.sh must do to go from OLD
#                                 (last initialized config) to NEW → IMPACT_*
# -----------------------------------------------------------------------------

cfg_meet_enabled() {
  local -n _c="$1"
  local a
  for a in ${_c[DEFAULT_APPS]:-}; do app_has_feature "$a" sfu && return 0; done
  return 1
}

# cfg_custom_url ARR APP — override from CUSTOM_APP_URLS or <prefix>/<app>.git
cfg_custom_url() {
  local -n _c="$1"
  local app="$2" pair
  for pair in ${_c[CUSTOM_APP_URLS]:-}; do
    [[ "${pair%%=*}" == "$app" ]] && { printf '%s' "${pair#*=}"; return 0; }
  done
  printf '%s/%s.git' "${_c[CUSTOM_APPS_GIT_PREFIX]:-}" "$app"
}

# compose_render ARR [--check] — writes $COMPOSE_FILE. Returns render's code
# (0 written/unchanged, 3 would change with --check).
compose_render() {
  local arr="$1"; shift
  local meet=0 expose
  cfg_meet_enabled "$arr" && meet=1
  local -n _cc="$arr"
  expose="${_cc[MARIADB_EXPOSE_PORT]:-0}"
  render "$TEMPLATE_DIR/docker-compose.yml.template" "$COMPOSE_FILE" --backup-dir "$BACKUP_DIR" "$@" -- \
    "COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME" \
    "HOST_HOME=$HOME" \
    "MEET_ENABLED=$meet" \
    "MARIADB_EXPOSE_PORT=$expose" \
    "SITE_NAME=${_cc[SITE_NAME]:-localhost}" \
    "TEST_SITE_NAME=${_cc[TEST_SITE_NAME]:-test.localhost}" \
    "TEST_MINIMAL_SITE_NAME=${_cc[TEST_MINIMAL_SITE_NAME]:-test-minimal.${_cc[SITE_NAME]:-localhost}}"
}

# cfg_impact OLD NEW — compares two configurations and fills:
#   IMPACT_LINES   human-readable "severity|change|what happens" entries
#   IMPACT_LEVEL   none | rerun | reconcile | rebuild
# severity: info (initialize.sh just applies it), reconcile (initialize.sh asks
# before changing/removing something), rebuild (data loss or manual action).
cfg_impact() {
  local -n _o="$1" _n="$2"
  IMPACT_LINES=(); IMPACT_LEVEL=none
  local rank_none=0 rank_rerun=1 rank_reconcile=2 rank_rebuild=3
  _bump() {
    local want="$1" cur_r want_r
    eval "cur_r=\$rank_$IMPACT_LEVEL; want_r=\$rank_$want"
    (( want_r > cur_r )) && IMPACT_LEVEL="$want"
    return 0
  }
  _imp() { IMPACT_LINES+=("$1|$2|$3"); case "$1" in info) _bump rerun ;; reconcile) _bump reconcile ;; rebuild) _bump rebuild ;; esac; }

  local a k
  # Frappe itself
  if [[ "${_o[FRAPPE_VERSION]:-}" != "${_n[FRAPPE_VERSION]:-}" ]]; then
    _imp rebuild "Frappe ${_o[FRAPPE_VERSION]:-?} → ${_n[FRAPPE_VERSION]:-?}" \
      "initialize.sh will offer to rebuild frappe-bench from scratch (sites are recreated, their data is lost)"
  fi
  # Default apps
  for a in ${_n[DEFAULT_APPS]:-}; do
    k="$(app_version_key "$a")"
    if [[ " ${_o[DEFAULT_APPS]:-} " != *" $a "* ]]; then
      _imp info "Add $a ${_n[$k]:-}" "initialize.sh fetches it and installs it on both sites"
    elif [[ "${_o[$k]:-}" != "${_n[$k]:-}" ]]; then
      _imp reconcile "$a ${_o[$k]:-?} → ${_n[$k]:-?}" "initialize.sh offers to switch the app's version and migrate the sites"
    fi
  done
  for a in ${_o[DEFAULT_APPS]:-}; do
    [[ " ${_n[DEFAULT_APPS]:-} " == *" $a "* ]] || \
      _imp reconcile "Remove $a" "initialize.sh offers to uninstall it from the sites and remove it from the bench"
  done
  # Custom apps
  local old_custom="" new_custom=""
  [[ "${_o[APPS_MODE]:-}" == custom ]] && old_custom="${_o[CUSTOM_APPS]:-}"
  [[ "${_n[APPS_MODE]:-}" == custom ]] && new_custom="${_n[CUSTOM_APPS]:-}"
  for a in $new_custom; do
    if [[ " $old_custom " != *" $a "* ]]; then
      _imp info "Add custom app $a" "initialize.sh clones it and installs it on both sites"
    elif [[ "$(cfg_custom_url "$1" "$a")" != "$(cfg_custom_url "$2" "$a")" ]]; then
      _imp reconcile "Custom app $a: new git URL" "initialize.sh offers to point the existing clone's origin to the new URL"
    fi
  done
  for a in $old_custom; do
    [[ " $new_custom " == *" $a "* ]] || \
      _imp reconcile "Remove custom app $a" "initialize.sh offers to uninstall it and remove it from the bench (the clone is moved to frappe-bench/archived/apps)"
  done
  if [[ "${_o[CORE_APP]:-}" != "${_n[CORE_APP]:-}" ]]; then
    _imp info "Core app ${_o[CORE_APP]:-none} → ${_n[CORE_APP]:-none}" "recorded for the frontend tooling (installed first)"
  fi
  if [[ "${_o[PLATFORM_URL]:-}" != "${_n[PLATFORM_URL]:-}" && -n "${_n[PLATFORM_URL]:-}" ]]; then
    _imp info "Platform repository → ${_n[PLATFORM_URL]}" "initialize.sh clones it into platform/ if that folder is missing"
  fi
  # Sites
  if [[ "${_o[SITE_NAME]:-}" != "${_n[SITE_NAME]:-}" ]]; then
    _imp reconcile "Site ${_o[SITE_NAME]:-?} → ${_n[SITE_NAME]:-?}" \
      "initialize.sh creates ${_n[SITE_NAME]}, ${_n[TEST_SITE_NAME]} and ${_n[TEST_MINIMAL_SITE_NAME]:-test-minimal.${_n[SITE_NAME]:-}}, then offers to drop the old sites; update your hosts file"
  fi
  if [[ "${_o[MAIN_SITE_DEVELOPER_MODE]:-}" != "${_n[MAIN_SITE_DEVELOPER_MODE]:-}" ]]; then
    _imp info "Main site developer mode → ${_n[MAIN_SITE_DEVELOPER_MODE]}" "applied to site_config.json by initialize.sh"
  fi
  # Secrets and services
  if [[ "${_o[ADMIN_PASSWORD]:-}" != "${_n[ADMIN_PASSWORD]:-}" ]]; then
    _imp reconcile "Administrator password changed" "initialize.sh offers to set it on the existing sites"
  fi
  if [[ "${_o[MARIADB_ROOT_PASSWORD]:-}" != "${_n[MARIADB_ROOT_PASSWORD]:-}" ]]; then
    _imp reconcile "MariaDB root password changed" \
      "the database volume still uses the old one: initialize.sh offers to change it in MariaDB (or wipe the volume with ./teardown.sh --volumes=mariadb)"
  fi
  if [[ "${_o[MARIADB_ROOT_USERNAME]:-}" != "${_n[MARIADB_ROOT_USERNAME]:-}" ]]; then
    _imp rebuild "MariaDB root user name changed" "the MariaDB image only creates 'root': a different name only works if you create that user yourself"
  fi
  for k in SEAWEEDFS_ACCESS_KEY SEAWEEDFS_SECRET_KEY JWT_SECRET WEBRTC_ANNOUNCED_IP MEET_ANNOUNCED_IP; do
    if [[ -n "${_n[$k]:-}" && "${_o[$k]:-}" != "${_n[$k]:-}" ]]; then
      _imp info "$k changed" "initialize.sh recreates the affected containers and rewrites the site configs"
    fi
  done
  if [[ "${_o[MARIADB_EXPOSE_PORT]:-}" != "${_n[MARIADB_EXPOSE_PORT]:-}" ]]; then
    _imp info "MariaDB host port $([[ ${_n[MARIADB_EXPOSE_PORT]} == 1 ]] && echo published || echo hidden)" "initialize.sh recreates the mariadb container (data is kept)"
  fi
  for a in ${_n[SEAWEEDFS_BUCKETS]:-}; do
    [[ " ${_o[SEAWEEDFS_BUCKETS]:-} " == *" $a "* ]] || _imp info "Add bucket $a" "created by initialize.sh"
  done
  for a in ${_o[SEAWEEDFS_BUCKETS]:-}; do
    [[ " ${_n[SEAWEEDFS_BUCKETS]:-} " == *" $a "* ]] || _imp info "Bucket $a no longer listed" "it is NOT deleted (initialize.sh only warns)"
  done
  unset -f _bump _imp
}

# cfg_print_impact — prints IMPACT_LINES nicely.
cfg_print_impact() {
  local l sev what how colour glyph
  for l in "${IMPACT_LINES[@]}"; do
    IFS='|' read -r sev what how <<< "$l"
    case "$sev" in
      info) colour="$C_BLUE"; glyph="$G_INFO" ;;
      reconcile) colour="$C_YELLOW"; glyph="$G_WARN" ;;
      rebuild) colour="$C_RED"; glyph="$G_FAIL" ;;
    esac
    printf '    %s%s%s %s\n      %s%s%s\n' "$colour" "$glyph" "$C_RESET" "$what" "$C_DIM" "$how" "$C_RESET"
    log_line "    [$sev] $what — $how"
  done
}

# Keys of setup.sh's configuration that may legitimately be empty.
cfg_mask() { local v="$1"; if [[ -z "$v" ]]; then printf '(not set)'; else printf '%s (%d chars)' "••••••••" "${#v}"; fi; }

# --- VS Code workspace ----------------------------------------------------------
# _ext_json INDENT — recommended extensions from vscode/extensions.list as JSON.
_ext_json() {
  local indent="$1" e json="" sep=""
  while IFS= read -r e || [[ -n "$e" ]]; do
    e="${e%%#*}"; e="${e//[[:space:]]/}"; [[ -z "$e" ]] && continue
    json+="$sep$indent\"$e\""; sep=$',\n'
  done < "$TEMPLATE_DIR/vscode/extensions.list"
  printf '%s' "$json"
}

# workspace_render — writes .vscode/dev.code-workspace: the repository root,
# ./platform when checked out, and every custom app present in the bench
# (CUSTOM_APPS of .env). Shared by initialize.sh, new-platform.sh, new-app.sh.
# Sets RENDER_STATUS.
workspace_render() {
  local -A _w=()
  [[ -f "$ENV_FILE" ]] && env_parse "$ENV_FILE" _w
  local folders='        { "path": ".." }' a
  [[ -d "$REPO_ROOT/platform/.git" ]] && folders+=$',\n'"        { \"path\": \"../platform\" }"
  for a in ${_w[CUSTOM_APPS]:-}; do
    [[ -d "$BENCH_DIR/apps/$a" ]] && folders+=$',\n'"        { \"path\": \"../frappe-bench/apps/$a\" }"
  done
  mkdir -p "$VSCODE_DIR"
  render "$TEMPLATE_DIR/vscode/dev.code-workspace.template" "$VSCODE_DIR/dev.code-workspace" --backup-dir "$BACKUP_DIR" -- \
    "FOLDERS_JSON=$folders" "EXTENSIONS_JSON=$(_ext_json '            ')"
}
