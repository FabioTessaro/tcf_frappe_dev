#!/usr/bin/env bash
# shellcheck disable=SC2034
# -----------------------------------------------------------------------------
# bootstrap/lib/apps.sh — default-app catalog, dependencies, versions.
# -----------------------------------------------------------------------------
# catalog_load                      read templates/apps.catalog
# apps_resolve "a b"                → APPS_RESOLVED (deps added, install order)
# app_version_key NAME              → NAME_VERSION
# app_has_feature NAME FEATURE
# git_refs URL                      → GIT_TAGS / GIT_BRANCHES (cached per run)
# git_ref_exists URL REF            → 0 exists, 1 missing, 2 unreachable
# pick_version LABEL URL CURRENT MAJOR → UI_VALUE
# -----------------------------------------------------------------------------

CATALOG_FILE="$TEMPLATE_DIR/apps.catalog"
CAT_NAMES=()
declare -gA CAT_REPO=() CAT_DEPS=() CAT_FEAT=() CAT_DESC=()

catalog_load() {
  CAT_NAMES=(); CAT_REPO=(); CAT_DEPS=(); CAT_FEAT=(); CAT_DESC=()
  [[ -f "$CATALOG_FILE" ]] || ui_die "App catalog not found: ${CATALOG_FILE#"$REPO_ROOT"/}"
  local name repo deps feat desc
  while IFS='|' read -r name repo deps feat desc || [[ -n "$name" ]]; do
    name="${name//[[:space:]]/}"
    [[ -z "$name" || "$name" == \#* ]] && continue
    valid_app_name "$name" || ui_die "apps.catalog: invalid app name '$name'"
    CAT_NAMES+=("$name")
    CAT_REPO[$name]="${repo//[[:space:]]/}"
    CAT_DEPS[$name]="${deps//[[:space:]]/}"
    CAT_FEAT[$name]="${feat//[[:space:]]/}"
    CAT_DESC[$name]="$desc"
  done < "$CATALOG_FILE"
  [[ -n "${CAT_REPO[frappe]:-}" ]] || ui_die "apps.catalog must contain a 'frappe' line."
  local a d
  for a in "${CAT_NAMES[@]}"; do
    for d in ${CAT_DEPS[$a]//,/ }; do
      [[ -n "${CAT_REPO[$d]:-}" ]] || ui_die "apps.catalog: '$a' depends on unknown app '$d'"
    done
  done
}

# Optional apps (everything except frappe), in catalog order.
catalog_optional() {
  local a; for a in "${CAT_NAMES[@]}"; do [[ "$a" != frappe ]] && printf '%s\n' "$a"; done
}

app_version_key() { printf '%s_VERSION' "${1^^}"; }

app_has_feature() { [[ ",${CAT_FEAT[$1]:-}," == *",$2,"* ]]; }

# apps_resolve "LIST" — adds missing dependencies (recursively) and sorts the
# result so dependencies come first; otherwise catalog order. frappe excluded.
# Sets APPS_RESOLVED (array) and APPS_ADDED (deps that were not in LIST).
apps_resolve() {
  local -A want=()
  local a d changed=true
  APPS_ADDED=()
  for a in $1; do want[$a]=1; done
  while [[ "$changed" == true ]]; do
    changed=false
    for a in "${!want[@]}"; do
      for d in ${CAT_DEPS[$a]//,/ }; do
        [[ "$d" == frappe ]] && continue
        if [[ -z "${want[$d]:-}" ]]; then want[$d]=1; APPS_ADDED+=("$d"); changed=true; fi
      done
    done
  done
  # Topological order, stable with respect to the catalog.
  APPS_RESOLVED=()
  local -A placed=()
  local progress=true ok
  while [[ "$progress" == true ]]; do
    progress=false
    for a in "${CAT_NAMES[@]}"; do
      [[ -n "${want[$a]:-}" && -z "${placed[$a]:-}" ]] || continue
      ok=true
      for d in ${CAT_DEPS[$a]//,/ }; do
        [[ "$d" == frappe ]] && continue
        [[ -n "${placed[$d]:-}" ]] || ok=false
      done
      if [[ "$ok" == true ]]; then APPS_RESOLVED+=("$a"); placed[$a]=1; progress=true; fi
    done
  done
  for a in "${!want[@]}"; do
    [[ -n "${placed[$a]:-}" ]] || ui_die "apps.catalog: circular dependency involving '$a'"
  done
}

# apps_dependents APP "LIST" — apps in LIST that depend on APP (directly).
apps_dependents() {
  local a out=()
  for a in $2; do [[ ",${CAT_DEPS[$a]:-}," == *",$1,"* ]] && out+=("$a"); done
  printf '%s' "${out[*]}"
}

# --- git refs ---------------------------------------------------------------------
GIT_TAGS=(); GIT_BRANCHES=()

_git_refs_cache_file() { printf '%s/refs-%s' "$STATE_TMP_DIR" "$(printf '%s' "$1" | md5sum | cut -c1-16)"; }

# git_refs_fetch URL — downloads the remote's refs into a per-run cache file
# (safe to run under ui_run, which uses a subshell). Returns 2 if unreachable.
git_refs_fetch() {
  local url="$1" file
  file="$(_git_refs_cache_file "$url")"
  [[ -s "$file" ]] && return 0
  if GIT_TERMINAL_PROMPT=0 timeout 60 git ls-remote --tags --heads "$url" > "$file.tmp"; then
    mv "$file.tmp" "$file"; return 0
  fi
  rm -f "$file.tmp"; return 2
}

# git_refs URL — fills GIT_TAGS (stable tags, newest first) and GIT_BRANCHES.
git_refs() {
  local url="$1" file
  file="$(_git_refs_cache_file "$url")"
  [[ -s "$file" ]] || git_refs_fetch "$url" 2>>"$LOG_FILE" || return 2
  mapfile -t GIT_TAGS < <(awk '{print $2}' "$file" | grep '^refs/tags/' \
    | sed 's#^refs/tags/##; s#\^{}$##' | grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -u | sort -rV)
  mapfile -t GIT_BRANCHES < <(awk '{print $2}' "$file" | grep '^refs/heads/' \
    | sed 's#^refs/heads/##' | sort -rV)
  return 0
}

git_ref_exists() {
  local url="$1" ref="$2" rc=0
  GIT_TERMINAL_PROMPT=0 timeout 60 git ls-remote --exit-code "$url" "refs/tags/$ref" "refs/heads/$ref" >/dev/null 2>&1 || rc=$?
  case "$rc" in 0) return 0 ;; 2) return 1 ;; *) return 2 ;; esac
}

# version_major REF — "v16.55.0" → 16, "version-15" → 15, else empty.
version_major() {
  if [[ "$1" =~ ^v?([0-9]+)(\.|$) ]]; then printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$1" =~ ^version-([0-9]+) ]]; then printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# pick_version LABEL URL [CURRENT] [MAJOR] — interactive tag/branch picker.
# MAJOR (optional) lists tags of that major version first.
pick_version() {
  local label="$1" url="$2" current="${3:-}" major="${4:-}"
  local limit="${VERSION_PICKER_LIMIT:-15}" view="main" t items i shown

  [[ -s "$(_git_refs_cache_file "$url")" ]] || \
    ui_run --quiet-fail "Listing versions of $label" -- git_refs_fetch "$url"
  if ! git_refs "$url"; then
    ui_warn "Couldn't list the versions of $label ($url) — enter one by hand (it can't be verified now)."
    ui_input --default "$current" --validate valid_env_value "$label version (tag or branch)"
    return 0
  fi

  while true; do
    items=()
    [[ -n "$current" ]] && items+=("=keep::Keep current: $current")
    case "$view" in
      main)
        shown=0
        for t in "${GIT_TAGS[@]}"; do
          if [[ -n "$major" && "$(version_major "$t")" != "$major" ]]; then continue; fi
          items+=("$t::$t"); shown=$((shown + 1))
          (( shown >= limit )) && break
        done
        (( shown == 0 )) && [[ -n "$major" ]] && items+=("=all::(no v$major.x tags found)")
        items+=("=all::More: all stable tags (${#GIT_TAGS[@]})")
        ;;
      all)
        for t in "${GIT_TAGS[@]}"; do items+=("$t::$t"); done
        items+=("=main::Back")
        ;;
      branches)
        for t in "${GIT_BRANCHES[@]}"; do items+=("$t::$t::branch"); done
        items+=("=main::Back")
        ;;
    esac
    [[ "$view" != branches ]] && items+=("=branches::More: branches (${#GIT_BRANCHES[@]})")
    items+=("=manual::Type a tag or branch…")

    local title="$label version"
    [[ -n "$major" && "$view" == main ]] && title+=" (v$major.x first — matches Frappe)"
    ui_select "$title" "${items[@]}" || return 1
    case "$UI_VALUE" in
      =keep) UI_VALUE="$current"; return 0 ;;
      =main|=all|=branches) view="${UI_VALUE#=}" ;;
      =manual)
        while true; do
          ui_input --validate valid_env_value "$label tag or branch"
          local typed="$UI_VALUE" rc=0
          git_ref_exists "$url" "$typed" || rc=$?
          case "$rc" in
            0) UI_VALUE="$typed"; return 0 ;;
            2) ui_warn "Couldn't reach $url to verify '$typed' — using it unverified."; UI_VALUE="$typed"; return 0 ;;
            *) ui_warn "'$typed' is not a tag or branch of $url." ;;
          esac
        done ;;
      *) return 0 ;;
    esac
  done
}
