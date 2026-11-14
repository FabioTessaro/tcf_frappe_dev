#!/usr/bin/env bash
# Shared helpers for the frontend development-toolchain bootstrap.
# Safe to source; this file does not install or change anything.

PIPELINE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(dirname "$PIPELINE_LIB_DIR")"
PIPELINE_BENCH_DIR="${BENCH_DIR:-$PIPELINE_ROOT/frappe-bench}"

pipeline_env_value() {
  local key="$1" file="${2:-$PIPELINE_ROOT/.env}" line value
  [[ -f "$file" ]] || return 0
  line=$(grep -E "^[[:space:]]*${key}=" "$file" | tail -n 1 || true)
  [[ -n "$line" ]] || return 0
  value="${line#*=}"
  value="${value%$'\r'}"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

pipeline_site_name() {
  local site_name="${SITE:-${TCF_SITE_NAME:-}}"
  [[ -n "$site_name" ]] || site_name="$(pipeline_env_value TCF_SITE_NAME)"
  [[ -n "$site_name" ]] || site_name='tcf.local'
  printf '%s' "$site_name"
}

pipeline_installed_apps() {
  local site="$1"
  [[ -x "$PIPELINE_BENCH_DIR/env/bin/bench" || -d "$PIPELINE_BENCH_DIR" ]] || return 1
  (cd "$PIPELINE_BENCH_DIR" && bench --site "$site" list-apps 2>/dev/null) || return 1
}

pipeline_app_is_installed() {
  local app="$1" apps_output="$2" line
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    line="${line%%[[:space:]]*}"
    [[ "$line" == "$app" ]] && return 0
  done <<< "$apps_output"
  return 1
}

pipeline_custom_apps() {
  local site="$1" apps_output app allowed_apps version_key
  local -a candidates=() installed=()

  apps_output=$(pipeline_installed_apps "$site") || return 1
  while IFS= read -r app; do
    app="${app//$'\r'/}"
    app="${app%%[[:space:]]*}"
    [[ "$app" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || continue
    installed+=("$app")
  done <<< "$apps_output"

  # TCF_APPS is the authoritative custom-app list initialised by bootstrap/setup-env.sh and extended by new-app.sh.
  # Intersect it with the apps actually installed on the site.
  allowed_apps="${TCF_APPS:-$(pipeline_env_value TCF_APPS)}"
  if [[ -n "$allowed_apps" ]]; then
    for app in $allowed_apps; do
      [[ "$app" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || continue
      [[ -d "$PIPELINE_BENCH_DIR/apps/$app" ]] || continue
      pipeline_app_is_installed "$app" "$apps_output" || continue
      candidates+=("$app")
    done
  else
    # Fallback for benches not managed by this repository: exclude standard
    # Frappe apps and every app represented by an *_VERSION key in .env.
    local excluded=" frappe erpnext hrms payments "
    while IFS= read -r version_key; do
      [[ -n "$version_key" ]] || continue
      app="${version_key%_VERSION}"
      app="${app,,}"
      excluded+="$app "
    done < <(grep -oE '^[[:space:]]*[A-Z0-9_]+_VERSION=' "$PIPELINE_ROOT/.env" 2>/dev/null | sed -E 's/^[[:space:]]*//; s/=$//' || true)

    for app in "${installed[@]}"; do
      [[ "$excluded" == *" $app "* ]] && continue
      [[ -d "$PIPELINE_BENCH_DIR/apps/$app" ]] || continue
      candidates+=("$app")
    done
  fi

  # Deduplicate while preserving the configured order.
  local -A seen=()
  for app in "${candidates[@]}"; do
    [[ -n "${seen[$app]:-}" ]] && continue
    seen[$app]=1
    printf '%s\n' "$app"
  done
}

pipeline_select_core_app() {
  local site="$1" selected="${CORE_APP:-}" item choice index=1
  local -a candidates=()

  mapfile -t candidates < <(pipeline_custom_apps "$site")
  if (( ${#candidates[@]} == 0 )); then
    echo "No installed custom apps found for site '$site'." >&2
    echo "Check TCF_APPS in .env and confirm those apps are installed on the site." >&2
    [[ -t 0 ]] && return 1 || return 2
  fi

  if [[ -n "$selected" ]]; then
    for item in "${candidates[@]}"; do
      if [[ "$item" == "$selected" ]]; then
        CORE_APP="$selected"
        export CORE_APP
        return 0
      fi
    done
    echo "CORE_APP '$selected' is not among the installed custom apps: ${candidates[*]}" >&2
    return 1
  fi

  if [[ ! -t 0 ]]; then
    if (( ${#candidates[@]} == 1 )); then
      CORE_APP="${candidates[0]}"
      export CORE_APP
      echo "Using the only installed custom app as core: $CORE_APP"
      return 0
    fi
    echo "Core app selection needs an interactive terminal. Available: ${candidates[*]}" >&2
    return 2
  fi

  echo "Select the core app from the custom apps installed on site '$site':"
  for item in "${candidates[@]}"; do
    printf '  %2d) %s\n' "$index" "$item"
    index=$((index + 1))
  done

  while true; do
    read -r -p "Core app [1-${#candidates[@]}]: " choice || return 1
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )); then
      CORE_APP="${candidates[$((choice - 1))]}"
      export CORE_APP
      echo "Selected core app: $CORE_APP"
      return 0
    fi
    printf 'Enter a number between 1 and %d.\n' "${#candidates[@]}"
  done
}
