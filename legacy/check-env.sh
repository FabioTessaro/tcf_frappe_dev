#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Audit of the TCF Frappe/Vue development container.
#
# Default mode is read-only: it reports missing prerequisites and scaffold gaps
# and never installs or modifies anything.
#
#   ./check-env.sh            audit the environment, scaffold and configuration
#   ./check-env.sh --run      also RUN the pipeline: typecheck, lint, style lint,
#                             format check and the unit/integration/contract
#                             tests. Writes only tool caches.
#   ./check-env.sh --build    --run plus the production build of the core app.
#                             Writes build output (public/frontend, www/portal.html,
#                             public/shared-assets).
#   -h, --help                show this help

set -uo pipefail

RUN_PIPELINE=false
RUN_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --run) RUN_PIPELINE=true ;;
    --build) RUN_PIPELINE=true; RUN_BUILD=true ;;
    -h|--help) sed -n '/^# Audit of/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-$SCRIPT_DIR}"
BENCH_DIR="${BENCH_DIR:-$WORKSPACE_DIR/frappe-bench}"
ENV_FILE="$WORKSPACE_DIR/.env"

read_env_value() {
  local key="$1" line value
  [[ -f "$ENV_FILE" ]] || return 0
  line=$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" | tail -n 1 || true)
  [[ -n "$line" ]] || return 0
  value="${line#*=}"
  value="${value%$'\r'}"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

SITE="${SITE:-${TCF_SITE_NAME:-$(read_env_value TCF_SITE_NAME)}}"
SITE="${SITE:-tcf.local}"
TCF_APPS="${TCF_APPS:-$(read_env_value TCF_APPS)}"
CORE_APP="${CORE_APP:-$(read_env_value CORE_APP)}"
FRONTEND_DIR="${FRONTEND_DIR:-}"
PYTHON="${PYTHON:-$BENCH_DIR/env/bin/python}"

MARIADB_ROOT_USERNAME="${MARIADB_ROOT_USERNAME:-$(read_env_value MARIADB_ROOT_USERNAME)}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-$(read_env_value MARIADB_ROOT_PASSWORD)}"
SEAWEEDFS_ENDPOINT="${SEAWEEDFS_ENDPOINT:-$(read_env_value SEAWEEDFS_ENDPOINT)}"

# provision-bench.sh installs uv tools in ~/.local/bin; Node is managed by nvm.
export PATH="$HOME/.local/bin:$PATH"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
  nvm use default --silent >/dev/null 2>&1 || true
fi

log_step "Auditing development environment"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0
TODO_COUNT=0

ok() {
  printf '  \033[32mOK\033[0m      %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf '  \033[31mMISSING\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
  printf '  \033[33mWARN\033[0m    %s\n' "$1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

skip() {
  printf '  \033[90mSKIP\033[0m    %s\n' "$1"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

# Work that is yours to do, not an environment problem: shown, counted, never a failure.
todo() {
  printf '  \033[36mTODO\033[0m    %s\n' "$1"
  TODO_COUNT=$((TODO_COUNT + 1))
}

done_item() {
  printf '  \033[32mDONE\033[0m    %s\n' "$1"
}

info() {
  printf '  \033[90mINFO\033[0m    %s\n' "$1"
}

section() {
  printf '\n== %s ==\n' "$1"
}

first_line() {
  local value="$1"
  printf '%s' "${value%%$'\n'*}"
}

check_command() {
  local label="$1" command_name="$2" version_args="$3" output
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "$label (command '$command_name' not found)"
    return
  fi

  # version_args is deliberately split into arguments (e.g. "--version").
  # All commands used here have simple, fixed version arguments.
  # shellcheck disable=SC2086
  if output=$("$command_name" $version_args 2>&1); then
    ok "$label — $(first_line "$output")"
  else
    fail "$label (found, but version check failed: $(first_line "$output"))"
  fi
}

check_file() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then ok "$label"; else fail "$label — $path"; fi
}

check_dir() {
  local label="$1" path="$2"
  if [[ -d "$path" ]]; then ok "$label"; else fail "$label — $path"; fi
}

check_any_file() {
  local label="$1" path
  shift
  for path in "$@"; do
    if [[ -f "$path" ]]; then
      ok "$label — ${path##*/}"
      return
    fi
  done
  fail "$label — expected one of: $*"
}

check_npm_script() {
  local label="$1" package_file="$FRONTEND_DIR/package.json"
  shift
  if [[ ! -f "$package_file" ]]; then
    fail "$label — frontend package.json not found"
    return
  fi
  if node -e '
    const pkg = require(process.argv[1]);
    const names = process.argv.slice(2);
    process.exit(names.some(name => typeof pkg.scripts?.[name] === "string") ? 0 : 1);
  ' "$package_file" "$@" >/dev/null 2>&1; then
    ok "$label — ${*}"
  else
    fail "$label — add a package.json script (accepted names: ${*})"
  fi
}

check_tcp() {
  local label="$1" host="$2" port="$3"
  if command -v timeout >/dev/null 2>&1; then
    if timeout 3 bash -c "exec 3<>/dev/tcp/\${1}/\${2}" _ "$host" "$port" >/dev/null 2>&1; then
      ok "$label — $host:$port"
    else
      fail "$label — cannot connect to $host:$port"
    fi
  else
    skip "$label — 'timeout' is unavailable, cannot safely test TCP connection"
  fi
}

# version_ge A B — success when version A >= version B (dotted numeric versions).
version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" == "$2" ]]
}

# min_version_of SPEC — extracts X.Y[.Z] from a ">=X.Y[.Z]" specifier; empty otherwise.
min_version_of() {
  local spec="${1//[[:space:]]/}"
  if [[ "$spec" =~ ^\>=([0-9]+(\.[0-9]+)*)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# json_field FILE JS_EXPRESSION — evaluates the expression against the parsed
# JSON file (as `pkg`) with Node and prints the result; prints nothing on error.
json_field() {
  command -v node >/dev/null 2>&1 || return 0
  node -e '
    try {
      const pkg = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      const value = eval(process.argv[2]);
      if (value !== undefined && value !== null) process.stdout.write(String(value));
    } catch {}
  ' "$1" "$2" 2>/dev/null
}

# parse_installed_apps — reads `bench execute frappe.get_installed_apps` output
# on stdin and prints one app name per line. Mirrors the frontend build's parser:
# Bench may print warnings first, so the last JSON-array line is used.
parse_installed_apps() {
  node -e '
    const lines = require("fs").readFileSync(0, "utf8").split(/\r?\n/).map((l) => l.trim());
    const line = [...lines].reverse().find((l) => l.startsWith("[") && l.endsWith("]"));
    try {
      const apps = JSON.parse(line ?? "");
      if (!Array.isArray(apps) || !apps.every((a) => typeof a === "string")) process.exit(1);
      process.stdout.write(apps.join("\n") + "\n");
    } catch { process.exit(1); }
  '
}

# abs_hook_path DIR — absolute path of DIR's git pre-commit hook.
abs_hook_path() {
  local dir="$1" hook
  hook=$(git -c safe.directory="$dir" -C "$dir" rev-parse --path-format=absolute --git-path hooks/pre-commit 2>/dev/null) || return 1
  printf '%s' "$hook"
}

# Select the portal's core app from apps installed on the target site and
# present in this bench. The standard Frappe platform apps are not candidates.
# Override CORE_APP_EXCLUDE to customise this list for a particular bench.
discover_custom_apps() {
  local apps_output app app_dir
  local -a candidates=()

  if ! command -v bench >/dev/null 2>&1 || [[ ! -d "$BENCH_DIR" ]]; then
    return 1
  fi
  if ! apps_output=$(cd "$BENCH_DIR" && bench --site "$SITE" list-apps 2>/dev/null); then
    return 1
  fi

  # TCF_APPS is the repository's declared custom-app list. Intersect it with
  # the site's installed apps so upstream Frappe apps are never offered as core.
  if [[ -n "$TCF_APPS" ]]; then
    for app in $TCF_APPS; do
      [[ "$app" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || continue
      app_dir="$BENCH_DIR/apps/$app"
      [[ -d "$app_dir" ]] || continue
      if printf '%s\n' "$apps_output" | grep -Eq "(^|[[:space:]])${app}([[:space:]]|$)"; then
        candidates+=("$app")
      fi
    done
  else
    local excluded_apps=" ${CORE_APP_EXCLUDE:-frappe erpnext hrms payments raven meet drive insights wiki helpdesk} "
    while IFS= read -r app; do
      app="${app//$'\r'/}"
      app="${app%%[[:space:]]*}"
      [[ "$app" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || continue
      [[ "$excluded_apps" == *" $app "* ]] && continue
      app_dir="$BENCH_DIR/apps/$app"
      [[ -d "$app_dir" ]] || continue
      candidates+=("$app")
    done <<< "$apps_output"
  fi

  printf '%s\n' "${candidates[@]}"
}

select_core_app() {
  local selected_index selection candidate index=1
  local -a custom_apps=()

  local discovered_apps
  if ! discovered_apps="$(discover_custom_apps)"; then
    fail "Unable to query installed apps on site '$SITE'. Check Bench and the site configuration."
    return 1
  fi

  if [[ -n "$discovered_apps" ]]; then
    mapfile -t custom_apps <<< "$discovered_apps"
  fi
  if (( ${#custom_apps[@]} == 0 )); then
    fail "Core app selection — no installed custom apps found for site '$SITE' in $BENCH_DIR/apps"
    printf '  Install the custom app on the site, or check SITE and BENCH_DIR.\n' >&2
    return 1
  fi

  if [[ -n "$CORE_APP" ]]; then
    for candidate in "${custom_apps[@]}"; do
      if [[ "$candidate" == "$CORE_APP" ]]; then
        ok "Core app selected — $CORE_APP (CORE_APP environment variable)"
        FRONTEND_DIR="${FRONTEND_DIR:-$BENCH_DIR/apps/$CORE_APP/frontend}"
        return 0
      fi
    done
    fail "CORE_APP '$CORE_APP' is not among the installed custom apps: ${custom_apps[*]}"
    return 1
  fi

  if [[ ! -t 0 ]]; then
    fail "Core app selection requires interactive input; set CORE_APP to one of: ${custom_apps[*]}"
    return 1
  fi

  printf '\nSelect the core app from the custom apps installed on site %s:\n' "$SITE"
  for candidate in "${custom_apps[@]}"; do
    printf '  %2d) %s\n' "$index" "$candidate"
    index=$((index + 1))
  done

  while true; do
    printf 'Core app [1-%d]: ' "${#custom_apps[@]}"
    if ! IFS= read -r selection; then
      fail "Core app selection — no selection was provided"
      return 1
    fi

    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#custom_apps[@]} )); then
      selected_index=$((selection - 1))
      CORE_APP="${custom_apps[$selected_index]}"
      FRONTEND_DIR="${FRONTEND_DIR:-$BENCH_DIR/apps/$CORE_APP/frontend}"
      ok "Core app selected — $CORE_APP"
      return 0
    fi

    printf 'Please enter a number between 1 and %d.\n' "${#custom_apps[@]}"
  done
}

# Resolve the core app before deriving any core-specific paths or running checks.
if ! select_core_app; then
  printf '\nEnvironment audit cannot continue without a valid core app selection.\n' >&2
  exit 1
fi

section "Container and base utilities"
check_command "Bash" bash "--version"
check_command "Git" git "--version"
check_command "curl" curl "--version"
check_command "jq" jq "--version"
check_command "unzip" unzip "-v"
check_command "timeout" timeout "--version"
check_command "Socket inspection (iproute2)" ss "--version"
check_command "uv" uv "--version"
check_command "pre-commit" pre-commit "--version"
check_command "Yarn" yarn "--version"

section "Frappe backend"
check_dir "Frappe bench directory" "$BENCH_DIR"
check_command "Bench CLI" bench "--version"
check_file "Bench virtual-environment Python" "$PYTHON"

if [[ -x "$PYTHON" && -d "$BENCH_DIR" ]]; then
  if (cd "$BENCH_DIR" && "$PYTHON" -c 'import frappe' >/dev/null 2>&1); then
    ok "Frappe importable from bench Python"
  else
    fail "Frappe is not importable from $PYTHON"
  fi
else
  skip "Frappe import check — bench Python or bench directory unavailable"
fi

SITE_DIR="$BENCH_DIR/sites/$SITE"
check_dir "Frappe site directory ($SITE)" "$SITE_DIR"
check_file "Site configuration ($SITE)" "$SITE_DIR/site_config.json"

if command -v bench >/dev/null 2>&1 && [[ -d "$SITE_DIR" ]]; then
  if apps_output=$(cd "$BENCH_DIR" && bench --site "$SITE" list-apps 2>&1); then
    if printf '%s\n' "$apps_output" | grep -Eq "(^|[[:space:]])${CORE_APP}([[:space:]]|$)"; then
      ok "Core app '$CORE_APP' installed on $SITE"
    else
      fail "Core app '$CORE_APP' is not listed on site $SITE"
    fi
  else
    fail "Cannot query installed apps on $SITE — $(first_line "$apps_output")"
  fi
else
  skip "Installed-app check — bench CLI or site directory unavailable"
fi

CORE_PYTHON_DIR="$BENCH_DIR/apps/$CORE_APP/$CORE_APP"

CORE_APP_DIR="$BENCH_DIR/apps/$CORE_APP"
CORE_PACKAGE_JSON="$CORE_APP_DIR/package.json"

if [[ -f "$CORE_PACKAGE_JSON" ]]; then
  if node -e '
    const pkg = require(process.argv[1]);
    const build = pkg.scripts?.build;

    const delegatesToFrontend =
      typeof build === "string" &&
      /pnpm\s+--dir\s+frontend\s+build/.test(build);

    const rootPinsPnpm =
      typeof pkg.packageManager === "string" &&
      pkg.packageManager.startsWith("pnpm@");

    process.exit(delegatesToFrontend && !rootPinsPnpm ? 0 : 1);
  ' "$CORE_PACKAGE_JSON" >/dev/null 2>&1; then
    ok "Core app build script delegates to frontend pnpm build"
  else
    fail "Core app root package.json has an incorrect build script or pnpm packageManager declaration"
  fi
fi
check_dir "Core Python package" "$CORE_PYTHON_DIR"
check_dir "Core backend tests" "$CORE_PYTHON_DIR/tests"

# Core Python scaffold (architecture guide, sections 9.16 and 14.6).
# Extend this list as the scaffold grows; it is the definition of "scaffold complete".
for scaffold_file in hooks.py modules.txt patches.txt config/__init__.py api/__init__.py \
  api/session.py api/apps.py tests/__init__.py tests/test_portal_page.py \
  tests/test_session_api.py tests/test_apps_api.py www/__init__.py www/portal.py; do
  check_file "Core scaffold: $scaffold_file" "$CORE_PYTHON_DIR/$scaffold_file"
done
# The portal page controller only runs if Frappe routes /portal paths to it.
if grep -q '"to_route": "portal"' "$CORE_PYTHON_DIR/hooks.py" 2>/dev/null; then
  ok "Core scaffold: hooks.py routes portal paths to the portal page"
else
  fail "Core scaffold: hooks.py has no website_route_rules entry with \"to_route\": \"portal\""
fi

if [[ -n "${TCF_APPS:-}" ]]; then
  for app in $TCF_APPS; do
    [[ "$app" == "$CORE_APP" ]] && continue
    app_python_dir="$BENCH_DIR/apps/$app/$app"
    check_dir "$app Python package ($app)" "$app_python_dir"
    check_dir "$app backend tests ($app)" "$app_python_dir/tests"
  done
else
  warn "TCF_APPS is not set; skipping custom feature-app package checks"
fi

section "Python runtime and frontend app discovery"
if [[ -f "$CORE_APP_DIR/pyproject.toml" && -x "$PYTHON" ]]; then
  python_required=$(sed -nE 's/^requires-python[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$CORE_APP_DIR/pyproject.toml" | head -n 1)
  python_min=$(min_version_of "$python_required")
  python_actual=$("$PYTHON" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true)
  if [[ -z "$python_min" ]]; then
    warn "Python requirement '$python_required' in pyproject.toml is not a simple '>=X.Y' specifier; version not checked"
  elif [[ -z "$python_actual" ]]; then
    fail "Cannot read the bench Python version from $PYTHON"
  elif version_ge "$python_actual" "$python_min"; then
    ok "Bench Python $python_actual satisfies requires-python $python_required"
  else
    fail "Bench Python $python_actual does not satisfy requires-python $python_required"
  fi
else
  skip "Python version check — pyproject.toml or bench Python unavailable"
fi

# The frontend build, tests and e2e config all learn the installed apps from this
# exact call, so it is audited directly rather than assumed.
if command -v bench >/dev/null 2>&1 && command -v node >/dev/null 2>&1 && [[ -d "$SITE_DIR" ]]; then
  if discovery_output=$(cd "$BENCH_DIR" && bench --site "$SITE" execute frappe.get_installed_apps 2>/dev/null); then
    if discovered_apps=$(printf '%s\n' "$discovery_output" | parse_installed_apps); then
      ok "Frontend app discovery: bench execute frappe.get_installed_apps returns a parseable app list"
      if printf '%s\n' "$discovered_apps" | grep -Fxq "$CORE_APP"; then
        ok "Discovery lists the core app ($CORE_APP)"
      else
        fail "Discovery does not list the core app ($CORE_APP)"
      fi
      frontend_apps=()
      while IFS= read -r discovered_app; do
        [[ -n "$discovered_app" && "$discovered_app" != "$CORE_APP" ]] || continue
        [[ -f "$BENCH_DIR/apps/$discovered_app/frontend/manifest.ts" ]] && frontend_apps+=("$discovered_app")
      done <<< "$discovered_apps"
      if (( ${#frontend_apps[@]} > 0 )); then
        ok "Feature apps with a frontend manifest: ${frontend_apps[*]}"
      else
        skip "No feature app has a frontend manifest yet (expected for a fresh scaffold)"
      fi
    else
      fail "bench execute frappe.get_installed_apps did not return a JSON app list; the frontend build and tests would fail"
    fi
  else
    fail "bench execute frappe.get_installed_apps failed on $SITE; the frontend build and tests would fail"
  fi
else
  skip "Frontend app discovery — bench CLI, Node.js or site directory unavailable"
fi

section "Backend services"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${MARIADB_ROOT_USERNAME:-root}"
DB_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"
if command -v mysqladmin >/dev/null 2>&1; then
  mysql_args=(--connect-timeout=3 -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER")
  [[ -n "$DB_PASSWORD" ]] && mysql_args+=("-p$DB_PASSWORD")
  mysql_args+=(--silent ping)
  if mysqladmin "${mysql_args[@]}" >/dev/null 2>&1; then
    ok "MariaDB reachable — $DB_HOST:$DB_PORT"
  else
    fail "MariaDB unreachable or credentials rejected — $DB_HOST:$DB_PORT"
  fi
else
  fail "MariaDB client — mysqladmin not found (install mariadb-client)"
fi

check_command "Redis CLI" redis-cli "--version"
if command -v redis-cli >/dev/null 2>&1; then
  for redis_host in "${REDIS_CACHE_HOST:-redis-cache}" "${REDIS_QUEUE_HOST:-redis-queue}"; do
    if redis_output=$(timeout 3 redis-cli -h "$redis_host" -p "${REDIS_PORT:-6379}" --no-auth-warning ping 2>&1) && [[ "$redis_output" == *PONG* ]]; then
      ok "Redis reachable — $redis_host:${REDIS_PORT:-6379}"
    else
      fail "Redis unreachable — $redis_host:${REDIS_PORT:-6379}"
    fi
  done
fi

SEAWEEDFS_URL="${SEAWEEDFS_ENDPOINT:-http://seaweedfs:8333}"
if command -v curl >/dev/null 2>&1; then
  http_code=$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' "$SEAWEEDFS_URL" 2>/dev/null || true)
  if [[ "$http_code" =~ ^[1-4][0-9][0-9]$ ]]; then
    ok "SeaweedFS HTTP endpoint reachable — $SEAWEEDFS_URL (HTTP $http_code)"
  else
    fail "SeaweedFS HTTP endpoint unavailable — $SEAWEEDFS_URL"
  fi
fi

check_tcp "Meet SFU signalling port" "${MEET_SFU_HOST:-meet-sfu}" "${MEET_SFU_PORT:-3000}"

section "Node and package manager"
check_command "Node.js" node "--version"
if command -v node >/dev/null 2>&1 && [[ -f "$FRONTEND_DIR/package.json" ]]; then
  node_required=$(json_field "$FRONTEND_DIR/package.json" 'pkg.engines && pkg.engines.node')
  node_min=$(min_version_of "$node_required")
  node_actual=$(node --version 2>/dev/null | sed 's/^v//')
  if [[ -z "$node_required" ]]; then
    warn "Frontend package.json declares no engines.node requirement"
  elif [[ -z "$node_min" ]]; then
    warn "engines.node '$node_required' is not a simple '>=X.Y' specifier; version not checked"
  elif version_ge "$node_actual" "$node_min"; then
    ok "Node.js $node_actual satisfies engines.node $node_required"
  else
    fail "Node.js $node_actual does not satisfy engines.node $node_required"
  fi
fi
check_command "Corepack" corepack "--version"
if command -v pnpm >/dev/null 2>&1; then
  if output=$(COREPACK_ENABLE_NETWORK=0 pnpm --version 2>&1); then
    ok "pnpm — $(first_line "$output")"
    pnpm_pin=$(json_field "$FRONTEND_DIR/package.json" 'pkg.packageManager')
    if [[ "$pnpm_pin" == pnpm@* ]]; then
      if [[ "${pnpm_pin#pnpm@}" == "$(first_line "$output")" ]]; then
        ok "Active pnpm matches the frontend packageManager pin ($pnpm_pin)"
      else
        fail "Active pnpm $(first_line "$output") differs from the frontend pin $pnpm_pin (run ./setup-env.sh)"
      fi
    fi
  else
    fail "pnpm command exists but is not usable from the local Corepack cache — $(first_line "$output")"
  fi
else
  fail "pnpm (command not found)"
fi

section "Frontend project"
check_dir "Core frontend directory" "$FRONTEND_DIR"
check_file "Frontend package.json" "$FRONTEND_DIR/package.json"
check_file "Frontend pnpm lockfile" "$FRONTEND_DIR/pnpm-lock.yaml"
if [[ -f "$FRONTEND_DIR/package.json" ]] && command -v node >/dev/null 2>&1; then
  if node -e 'const p=require(process.argv[1]); process.exit(typeof p.packageManager === "string" && p.packageManager.startsWith("pnpm@") ? 0 : 1)' "$FRONTEND_DIR/package.json" >/dev/null 2>&1; then
    ok "Frontend packageManager pins pnpm"
  else
    fail "Frontend package.json must pin pnpm with the packageManager field"
  fi
fi
check_dir "Frontend node_modules" "$FRONTEND_DIR/node_modules"

if [[ -d "$FRONTEND_DIR" && -f "$FRONTEND_DIR/package.json" ]] && command -v node >/dev/null 2>&1; then
  # Every dependency declared in package.json must be installed. The list comes
  # from the manifest itself, so it can never drift from what the project needs.
  declared_modules=()
  while IFS= read -r module; do
    [[ -n "$module" ]] && declared_modules+=("$module")
  done < <(node -e '
    const pkg = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const names = Object.keys({ ...pkg.dependencies, ...pkg.devDependencies }).sort();
    process.stdout.write(names.join("\n") + "\n");
  ' "$FRONTEND_DIR/package.json" 2>/dev/null)

  missing_modules=0
  for module in "${declared_modules[@]}"; do
    if [[ ! -f "$FRONTEND_DIR/node_modules/$module/package.json" ]]; then
      fail "Frontend dependency not installed: $module"
      missing_modules=$((missing_modules + 1))
    fi
  done
  if (( ${#declared_modules[@]} == 0 )); then
    fail "No dependencies could be read from the frontend package.json"
  elif (( missing_modules == 0 )); then
    ok "All ${#declared_modules[@]} dependencies declared in package.json are installed"
  fi

  # Lockfile and manifest must agree. Frozen + lockfile-only + offline: nothing is
  # installed, downloaded or written.
  if command -v pnpm >/dev/null 2>&1; then
    lock_output=$(cd "$FRONTEND_DIR" && COREPACK_ENABLE_NETWORK=0 pnpm install --frozen-lockfile --lockfile-only --offline 2>&1)
    lock_status=$?
    if (( lock_status == 0 )); then
      ok "pnpm-lock.yaml is in sync with package.json"
    elif grep -qE 'NO_OFFLINE_META|META_FETCH_FAIL' <<<"$lock_output"; then
      # pnpm re-checks the lockfile against registry metadata, which it can only read from its
      # local cache while offline. That says nothing about the lockfile itself.
      warn "pnpm-lock.yaml could not be verified offline (pnpm's metadata cache is incomplete); run 'pnpm install --frozen-lockfile' to verify it"
    else
      fail "pnpm-lock.yaml is out of sync with package.json (run: pnpm install --lockfile-only)"
    fi
  fi
else
  skip "Frontend dependency resolution — frontend directory/package or Node.js missing"
fi

section "Frontend build and test configuration"
check_file "Vite configuration" "$FRONTEND_DIR/vite.config.ts"
check_file "Vitest configuration" "$FRONTEND_DIR/vitest.config.ts"
check_file "Playwright configuration" "$FRONTEND_DIR/playwright.config.ts"
check_file "Tailwind preset" "$FRONTEND_DIR/tailwind.preset.ts"
check_file "Tailwind configuration" "$FRONTEND_DIR/tailwind.config.ts"
check_file "TypeScript configuration" "$FRONTEND_DIR/tsconfig.json"
check_any_file "ESLint flat configuration" \
  "$FRONTEND_DIR/eslint.config.js" "$FRONTEND_DIR/eslint.config.mjs" "$FRONTEND_DIR/eslint.config.cjs"
check_any_file "Stylelint configuration" \
  "$FRONTEND_DIR/stylelint.config.js" "$FRONTEND_DIR/.stylelintrc" "$FRONTEND_DIR/.stylelintrc.json" "$FRONTEND_DIR/.stylelintrc.cjs"
check_file "TCF Stylelint architecture plugin" "$FRONTEND_DIR/stylelint/tcf-architecture.js"
check_file "Prettier configuration" "$FRONTEND_DIR/prettier.config.js"
check_file "Prettier ignore file" "$FRONTEND_DIR/.prettierignore"
check_file "Vitest global setup" "$FRONTEND_DIR/tests/setup.ts"
check_dir "Integration tests directory" "$FRONTEND_DIR/tests/integration"
check_dir "Contract tests directory" "$FRONTEND_DIR/tests/contract"
check_dir "E2E tests directory" "$FRONTEND_DIR/tests/e2e"

section "Core frontend scaffold"
# Files and folders every core app must have to conform to the architecture guide.
# Extend this list as the scaffold grows; it is the definition of "scaffold complete".
scaffold_files=(
  pnpm-workspace.yaml postcss.config.js
  plugins/discover-apps.ts plugins/emit-shared-assets.ts plugins/copy-index-html.ts
  plugins/find-frappe-package.ts plugins/workspace.ts
  src/registry.d.ts
  src/sdk/index.ts src/sdk/define-app.ts src/sdk/manifest.types.ts
  src/sdk/nav.types.ts src/sdk/route-meta.types.ts
  src/styles/main.scss src/styles/tailwind.css
  src/styles/abstracts/_index.scss src/styles/abstracts/_variables.scss
  src/styles/abstracts/_mixins.scss src/styles/abstracts/_functions.scss
  src/styles/themes/_tokens.scss src/styles/themes/_light.scss
  src/styles/themes/_dark.scss src/styles/themes/_app-themable.scss
  tests/mocks/server.ts tests/mocks/handlers/index.ts
  tests/utils/render.ts tests/utils/fake-router.ts
  tests/contract/manifests.test.ts tests/contract/tokens.test.ts
  tests/contract/locales-parity.test.ts tests/contract/portal-path.test.ts
  tests/integration/login-wall.test.ts tests/plugins/discover-apps.test.ts
  tests/mocks/fixtures/index.ts tests/mocks/fixtures/users.ts tests/mocks/fixtures/apps.ts
  index.html src/env.d.ts public/favicon.svg
  eslint.boundaries.js eslint.boundaries.d.ts tsconfig.e2e.json
  scripts/lint-apps.mjs scripts/generate-icon-names.mjs
  plugins/icon-delivery.ts plugins/icon-set.ts
  tests/contract/boundaries.test.ts tests/contract/icons.test.ts
  tests/contract/typography.test.ts tests/contract/breakpoints.test.ts
  tests/integration/session-expiry.test.ts tests/integration/role-guard.test.ts
  tests/integration/registry.test.ts
  tests/plugins/fixtures.ts tests/plugins/emit-shared-assets.test.ts
  tests/utils/typography-contract.ts tests/utils/typography-contract.test.ts
  tests/e2e/global-setup.ts tests/e2e/fixtures/index.ts tests/e2e/fixtures/users.ts
  tests/e2e/pages/index.ts tests/e2e/pages/portal-page.ts tests/e2e/pages/login-page.ts
  tests/e2e/pages/launcher-page.ts tests/e2e/pages/not-found-page.ts
  tests/e2e/pages/app-shell-page.ts
  tests/e2e/specs/login-wall.spec.ts tests/e2e/specs/launcher.spec.ts
  tests/e2e/specs/session-expiry.spec.ts tests/e2e/specs/connection.spec.ts
  tests/e2e/specs/chunk-reload.spec.ts tests/e2e/specs/public-site.spec.ts
  src/styles/typography/_index.scss src/styles/typography/_roles.scss
  src/styles/typography/_resolve.scss src/styles/typography/typefaces/_index.scss
  src/styles/typography/scripts/_index.scss src/styles/typography/scripts/_latin.scss
  src/styles/typography/scripts/_japanese.scss
  src/styles/typography/scripts/_chinese-simplified.scss
  src/styles/typography/scripts/_chinese-traditional.scss
  src/styles/typography/devices/_index.scss src/styles/typography/devices/_desktop.scss
  src/styles/typography/devices/_mobile.scss
  src/styles/base/_reset.scss src/styles/base/_elements.scss
  src/styles/vendor/_third-party-overrides.scss
  src/shared/components/index.ts src/shared/components/primitives/Icon/icons.json
  src/shared/constants/roles.ts src/shared/constants/limits.ts src/shared/constants/breakpoints.ts
  src/shared/types/index.ts src/shared/types/common.types.ts
  src/shared/utils/format.ts src/shared/utils/date.ts src/shared/utils/string.ts
  src/shared/utils/validators.ts
  src/shared/composables/index.ts src/shared/composables/useDebounce.ts
  src/shared/composables/useMediaQuery.ts src/shared/composables/useOnlineStatus.ts
  src/shared/composables/useLanguage.ts
  src/shared/stores/index.ts src/shared/stores/ui.store.ts
  src/shared/directives/index.ts src/shared/directives/click-outside.ts
  src/shared/directives/focus.ts
  src/shared/frappe/client.ts src/shared/frappe/call.ts src/shared/frappe/errors.ts
  src/shared/frappe/resource.ts src/shared/frappe/realtime.ts src/shared/frappe/permissions.ts
  src/shared/i18n/detect-language.ts
  src/app/providers/directives.ts src/app/providers/theme.ts
  src/app/providers/frappe-client.ts
  src/sdk/permissions.ts src/sdk/permissions.test.ts
  src/shared/index.ts
  src/shared/constants/index.ts src/shared/constants/portal.ts src/shared/constants/storage-keys.ts
  src/shared/utils/index.ts src/shared/utils/portal-path.ts src/shared/utils/portal-path.test.ts
  src/shared/frappe/index.ts src/shared/frappe/types.ts
  src/shared/frappe/session.ts src/shared/frappe/session.test.ts
  src/shared/i18n/index.ts src/shared/i18n/languages.ts src/shared/i18n/languages.test.ts
  src/shared/i18n/merge-locales.ts src/shared/i18n/merge-locales.test.ts
  src/shared/i18n/apply-language.ts src/shared/i18n/apply-language.test.ts
  src/shared/i18n/locales/en.json
  src/app/main.ts src/app/App.vue src/app/App.scss src/app/App.test.ts
  src/app/layouts/index.ts
  src/app/providers/index.ts src/app/providers/pinia.ts src/app/providers/i18n.ts
  src/app/providers/i18n.test.ts src/app/providers/error-handler.ts
  src/app/providers/error-handler.test.ts src/app/providers/app-registry.ts
  src/app/router/index.ts src/app/router/routes.ts src/app/router/route-meta.d.ts
  src/app/router/guards.ts src/app/router/guards.test.ts
  src/app/router/register-apps.ts src/app/router/register-apps.test.ts
  src/platform/auth/index.ts src/platform/auth/routes.ts src/platform/auth/locales/en.json
  src/platform/auth/types/index.ts src/platform/auth/types/session.types.ts
  src/platform/auth/stores/session.store.ts src/platform/auth/stores/session.store.test.ts
  src/platform/launcher/index.ts src/platform/launcher/routes.ts
  src/platform/launcher/locales/en.json
)
# Component folders follow the guide's pattern (9.7): template, own stylesheet, test, re-export.
for component_folder in \
  app/layouts/AuthLayout app/layouts/LauncherLayout app/layouts/AppShellLayout \
  platform/auth/views/LoginView platform/auth/views/ForgotPasswordView \
  platform/launcher/views/LauncherView platform/launcher/views/NotFoundView; do
  component_name="${component_folder##*/}"
  for suffix in vue scss test.ts; do
    scaffold_files+=("src/$component_folder/$component_name.$suffix")
  done
  scaffold_files+=("src/$component_folder/index.ts")
done
for scaffold_file in "${scaffold_files[@]}"; do
  check_file "Scaffold: $scaffold_file" "$FRONTEND_DIR/$scaffold_file"
done
for category in primitives forms overlays data feedback navigation layout; do
  check_file "Scaffold: shared/components/$category barrel" "$FRONTEND_DIR/src/shared/components/$category/index.ts"
done
# The feature-slice folders of the platform features (guide, section 9.6), for you to fill.
for slice_dir in platform/auth/api platform/auth/components platform/auth/composables \
  platform/launcher/api platform/launcher/components platform/launcher/composables \
  platform/launcher/stores platform/launcher/types src/assets/brand src/assets/images; do
  check_dir "Scaffold: ${slice_dir#src/}" "$FRONTEND_DIR/${slice_dir/#platform/src/platform}"
done
for workflow in ci.yml bench.yml; do
  check_file "Scaffold: .github/workflows/$workflow" "$CORE_APP_DIR/.github/workflows/$workflow"
done
for scaffold_dir in tests/e2e/fixtures tests/e2e/pages tests/e2e/specs tests/mocks/fixtures; do
  check_dir "Scaffold: $scaffold_dir" "$FRONTEND_DIR/$scaffold_dir"
done

# Repository hygiene for the core app.
if [[ -f "$CORE_APP_DIR/.eslintrc" ]]; then
  warn "Legacy $CORE_APP/.eslintrc is present; ESLint 10 uses frontend/eslint.config.js only"
else
  ok "No legacy .eslintrc next to the flat ESLint config"
fi
if [[ -f "$CORE_APP_DIR/.gitignore" ]]; then
  for ignored in "$CORE_APP/public/frontend/" "$CORE_APP/public/shared-assets/" "$CORE_APP/www/portal.html"; do
    if grep -qxF "$ignored" "$CORE_APP_DIR/.gitignore"; then
      ok "Generated output is git-ignored: $ignored"
    else
      fail "Generated output is not git-ignored: $ignored (add it to $CORE_APP/.gitignore)"
    fi
  done
else
  fail "Core app .gitignore — $CORE_APP_DIR/.gitignore"
fi

# ------------------------------------------------------------------------------------
# Your implementation work. Never an error: the scaffold is complete when everything above
# passes; these lines show how much of the core app itself is still yours to build.
# ------------------------------------------------------------------------------------
section "Your implementation work (not errors)"
STYLES_DIR="$FRONTEND_DIR/src/styles"
SRC_DIR="$FRONTEND_DIR/src"

# 1. Typography: at least one typeface forwarded in typefaces/_index.scss.
typefaces_index="$STYLES_DIR/typography/typefaces/_index.scss"
typeface_count=0
if [[ -f "$typefaces_index" ]]; then
  typeface_count=$(grep -v '^[[:space:]]*//' "$typefaces_index" | grep -c '@forward' || true)
fi
if (( typeface_count > 0 )); then
  done_item "1. Typography: $typeface_count typeface(s) registered"
else
  todo "1. Typography: no typeface registered (src/styles/typography). Fonts go in src/assets/fonts first"
fi

# 2. Icons: files installed, delivery implemented, installed names listed.
icon_files=0
if [[ -d "$SRC_DIR/assets/icons" ]]; then
  icon_files=$(find "$SRC_DIR/assets/icons" -type f ! -name '.gitkeep' | wc -l)
fi
if (( icon_files > 0 )); then
  done_item "2. Icons: Material files installed in src/assets/icons"
else
  todo "2. Icons: no icon files in src/assets/icons yet"
fi
if grep -q 'export const iconDelivery: IconDelivery = notConfiguredIconDelivery' "$FRONTEND_DIR/plugins/icon-delivery.ts" 2>/dev/null; then
  todo "2. Icons: delivery not configured (plugins/icon-delivery.ts)"
else
  done_item "2. Icons: delivery configured"
fi
if grep -Eq 'return null;' "$FRONTEND_DIR/plugins/icon-set.ts" 2>/dev/null; then
  todo "2. Icons: installed icon names not listed (plugins/icon-set.ts), so the icons contract cannot check names"
else
  done_item "2. Icons: installed icon names listed"
fi

# 3. Theming: informational.
token_count=$(cat "$STYLES_DIR"/themes/_*.scss 2>/dev/null | grep -oE '^[[:space:]]*--tcf-[a-z0-9-]+' | sort -u | wc -l)
info "3. Theming: $token_count design tokens declared (expand tokens and palettes in src/styles/themes)"

# 4. Shared components: component folders (with a .vue file) per category.
component_total=0
for category in primitives forms overlays data feedback navigation layout; do
  category_dir="$SRC_DIR/shared/components/$category"
  count=0
  if [[ -d "$category_dir" ]]; then
    count=$(find "$category_dir" -mindepth 2 -maxdepth 2 -name '*.vue' | wc -l)
  fi
  component_total=$((component_total + count))
done
if (( component_total > 0 )); then
  done_item "4. Shared components: $component_total component(s) built"
else
  todo "4. Shared components: none built yet (primitives, forms, overlays, data, feedback, navigation, layout)"
fi

# 5. Shared layers: seeds exist; count what is there.
count_units() {
  find "$1" -maxdepth 1 -type f -name '*.ts' ! -name 'index.ts' ! -name '*.test.ts' 2>/dev/null | wc -l
}
info "5. Shared layers: $(count_units "$SRC_DIR/shared/composables") composable(s), $(count_units "$SRC_DIR/shared/stores") store(s), $(count_units "$SRC_DIR/shared/directives") directive(s), $(count_units "$SRC_DIR/shared/utils") util module(s), $(grep -c '{ code: "' "$SRC_DIR/shared/i18n/languages.ts" 2>/dev/null || echo 0) language(s) registered"

# 6. Pages: platform views that still carry the stub marker.
stub_pages=$(grep -rl 'TCF-STUB' "$SRC_DIR/platform" 2>/dev/null | wc -l)
if (( stub_pages > 0 )); then
  todo "6. Pages: $stub_pages platform page(s) are still stubs (search src/platform for TCF-STUB)"
else
  done_item "6. Pages: no stub pages left in src/platform"
fi

# 7. Backend: the API modules and doctypes.
for api_module in session apps; do
  if [[ -f "$CORE_PYTHON_DIR/api/$api_module.py" ]]; then
    done_item "7. Backend: api/$api_module.py exists"
  else
    todo "7. Backend: api/$api_module.py not written yet"
  fi
done
if [[ -n "$(find "$CORE_PYTHON_DIR" -type d -name doctype 2>/dev/null | head -n 1)" ]]; then
  done_item "7. Backend: doctypes exist"
else
  todo "7. Backend: no doctypes yet"
fi

if [[ -f "$CORE_APP_DIR/.gitignore" ]]; then
  for ignored in "frontend/src/icon-names.d.ts" "frontend/tests/e2e/.auth/"; do
    if grep -qxF "$ignored" "$CORE_APP_DIR/.gitignore"; then
      ok "Generated or local output is git-ignored: $ignored"
    else
      fail "Not git-ignored: $ignored (add it to $CORE_APP/.gitignore)"
    fi
  done
fi

section "Frontend package scripts"
check_npm_script "Vite development server script" dev
check_npm_script "Production build script" build
check_npm_script "Type-check script" typecheck type-check
check_npm_script "ESLint script" lint
check_npm_script "Stylelint script" lint:styles stylelint
check_npm_script "Prettier formatting script" format
check_npm_script "Prettier formatting check script" format:check
check_npm_script "Unit-test script" test:unit test
check_npm_script "Integration-test script" test:integration
check_npm_script "Contract-test script" test:contract
check_npm_script "Playwright E2E script" test:e2e
check_npm_script "Feature-app lint script" lint:apps
check_npm_script "Icon-name generation script" generate:icons
check_npm_script "Coverage script" test:coverage

# New installs seed package.json from this template; drift means a fresh bench would
# get different scripts than the core app actually uses.
SCRIPTS_TEMPLATE="$SCRIPT_DIR/bootstrap/templates/frontend.package.json.template"
if [[ -f "$SCRIPTS_TEMPLATE" && -f "$FRONTEND_DIR/package.json" ]] && command -v node >/dev/null 2>&1; then
  script_drift=$(node -e '
    const fs = require("fs");
    const template = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).scripts ?? {};
    const actual = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).scripts ?? {};
    const names = [...new Set([...Object.keys(template), ...Object.keys(actual)])].sort();
    for (const name of names) {
      if (template[name] !== actual[name]) {
        const kind = template[name] === undefined ? "only in the app" : actual[name] === undefined ? "only in the template" : "different";
        console.log(`${name} (${kind})`);
      }
    }
  ' "$SCRIPTS_TEMPLATE" "$FRONTEND_DIR/package.json" 2>/dev/null)
  if [[ -z "$script_drift" ]]; then
    ok "Frontend scripts match the bootstrap template"
  else
    while IFS= read -r drifted; do
      warn "Script differs from bootstrap/templates/frontend.package.json.template: $drifted"
    done <<< "$script_drift"
  fi
fi

section "Playwright browser"
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
if [[ -d "$PLAYWRIGHT_BROWSERS_PATH" ]] && find "$PLAYWRIGHT_BROWSERS_PATH" -maxdepth 2 -type d -name 'chromium-*' -print -quit 2>/dev/null | grep -q .; then
  ok "Playwright Chromium browser cache — $PLAYWRIGHT_BROWSERS_PATH"
else
  fail "Playwright Chromium browser not found — expected under $PLAYWRIGHT_BROWSERS_PATH"
fi

section "VS Code Server extensions"
REQUIRED_EXTENSIONS=(
  "ms-python.python"
  "ms-python.vscode-pylance"
  "Vue.volar"
  "dbaeumer.vscode-eslint"
  "stylelint.vscode-stylelint"
  "bradlc.vscode-tailwindcss"
  "mrmlnc.vscode-scss"
  "wholroyd.jinja"
  "esbenp.prettier-vscode"
  "ms-playwright.playwright"
)

INSTALLED_EXTENSIONS=""
if command -v code >/dev/null 2>&1; then
  INSTALLED_EXTENSIONS=$(code --list-extensions 2>/dev/null || true)
fi

if [[ -z "$INSTALLED_EXTENSIONS" ]]; then
  extension_dirs=(
    "${VSCODE_EXTENSIONS_DIR:-$HOME/.vscode-server/extensions}"
    "$HOME/.vscode-server-insiders/extensions"
  )
  for extension_dir in "${extension_dirs[@]}"; do
    [[ -d "$extension_dir" ]] || continue
    while IFS= read -r extension_name; do
      [[ -n "$extension_name" ]] && INSTALLED_EXTENSIONS+="$extension_name"$'\n'
    done < <(find "$extension_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null)
  done

  # Some VS Code Server builds keep extensions under a versioned server folder.
  if [[ -d "$HOME/.vscode-server/cli/servers" ]]; then
    while IFS= read -r extension_name; do
      [[ -n "$extension_name" ]] && INSTALLED_EXTENSIONS+="$extension_name"$'\n'
    done < <(find "$HOME/.vscode-server/cli/servers" -mindepth 4 -maxdepth 4 -type d -path '*/server/extensions/*' -printf '%f\n' 2>/dev/null)
  fi
fi

for extension in "${REQUIRED_EXTENSIONS[@]}"; do
  extension_prefix="${extension,,}-"
  found=false
  while IFS= read -r installed; do
    installed_lower="${installed,,}"
    if [[ "$installed_lower" == "${extension,,}" || "$installed_lower" == "$extension_prefix"* ]]; then
      found=true
      break
    fi
  done <<< "$INSTALLED_EXTENSIONS"
  if [[ "$found" == true ]]; then
    ok "VS Code extension: $extension"
  else
    fail "VS Code extension missing: $extension"
  fi
done

section "Git hooks and local workflow"
if [[ -f "$WORKSPACE_DIR/.pre-commit-config.yaml" ]]; then
  ok "Repository pre-commit configuration"
else
  warn "No root .pre-commit-config.yaml; app-level hooks may still be configured separately"
fi
if command -v git >/dev/null 2>&1 && git -c safe.directory="$WORKSPACE_DIR" -C "$WORKSPACE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  hook_path=$(abs_hook_path "$WORKSPACE_DIR" || true)
  if [[ -n "$hook_path" && -x "$hook_path" ]]; then
    ok "Git pre-commit hook installed for the workspace repository"
  else
    warn "Git pre-commit hook not installed for the workspace repository"
  fi
else
  skip "Git hook check — workspace is not a Git working tree"
fi

# Every custom app is its own repository with its own hook (new-app.sh installs it).
hook_apps=("$CORE_APP")
for app in ${TCF_APPS:-}; do
  [[ "$app" == "$CORE_APP" ]] || hook_apps+=("$app")
done
for app in "${hook_apps[@]}"; do
  app_dir="$BENCH_DIR/apps/$app"
  [[ -d "$app_dir" ]] || continue
  if ! command -v git >/dev/null 2>&1 || [[ "$(git -c safe.directory="$app_dir" -C "$app_dir" rev-parse --show-toplevel 2>/dev/null)" != "$(cd "$app_dir" && pwd -P)" ]]; then
    skip "Pre-commit hook ($app) — not a Git repository of its own"
  elif [[ ! -f "$app_dir/.pre-commit-config.yaml" ]]; then
    warn "$app has no .pre-commit-config.yaml"
  else
    hook_path=$(abs_hook_path "$app_dir" || true)
    if [[ -n "$hook_path" && -x "$hook_path" ]]; then
      ok "Git pre-commit hook installed in $app"
    else
      warn "Git pre-commit hook not installed in $app (run: cd $app_dir && pre-commit install)"
    fi
  fi
done

section "Running processes (informational)"
if command -v ss >/dev/null 2>&1; then
  for port in 8000 9000 5173; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then
      ok "Local port $port is listening"
    else
      skip "Local port $port is idle (normal when the corresponding server is stopped)"
    fi
  done
fi

# Vite proxies API calls to this target; informational because the bench is often stopped.
PROXY_TARGET="${FRAPPE_PROXY_TARGET:-$(read_env_value FRAPPE_PROXY_TARGET)}"
PROXY_TARGET="${PROXY_TARGET:-http://frappe:8000}"
if command -v curl >/dev/null 2>&1; then
  ping_body=$(curl -sS --max-time 3 -H "Host: $SITE" "$PROXY_TARGET/api/method/ping" 2>/dev/null || true)
  if [[ "$ping_body" == *pong* ]]; then
    ok "Frappe answers at the Vite proxy target — $PROXY_TARGET (site $SITE)"
  else
    skip "Frappe is not answering at $PROXY_TARGET (normal while the bench is stopped)"
  fi
fi

# Runs one pipeline command in DIR, reporting duration and the tail of its output on failure.
run_pipeline_step() {
  local label="$1" dir="$2" log started
  shift 2
  log=$(mktemp)
  started=$SECONDS
  if (cd "$dir" && COREPACK_ENABLE_NETWORK=0 "$@") >"$log" 2>&1; then
    ok "$label ($((SECONDS - started))s)"
  else
    fail "$label — failed after $((SECONDS - started))s"
    tail -n 15 "$log" | sed 's/^/           /'
  fi
  rm -f "$log"
}

if [[ "$RUN_PIPELINE" == true ]]; then
  section "Pipeline run"
  if ! command -v pnpm >/dev/null 2>&1 || [[ ! -d "$FRONTEND_DIR/node_modules" ]]; then
    fail "Pipeline run — pnpm or the frontend dependencies are missing; fix the sections above first"
  else
    export TCF_SITE_NAME="$SITE"
    run_pipeline_step "Type check (pnpm typecheck)" "$FRONTEND_DIR" pnpm typecheck
    run_pipeline_step "ESLint (pnpm lint)" "$FRONTEND_DIR" pnpm lint
    run_pipeline_step "Feature-app lint (pnpm lint:apps)" "$FRONTEND_DIR" pnpm lint:apps
    run_pipeline_step "Stylelint (pnpm lint:styles)" "$FRONTEND_DIR" pnpm lint:styles
    run_pipeline_step "Prettier (pnpm format:check)" "$FRONTEND_DIR" pnpm format:check
    run_pipeline_step "Unit tests (pnpm test:unit)" "$FRONTEND_DIR" pnpm test:unit
    run_pipeline_step "Integration tests (pnpm test:integration)" "$FRONTEND_DIR" pnpm test:integration
    run_pipeline_step "Contract tests (pnpm test:contract)" "$FRONTEND_DIR" pnpm test:contract
    run_pipeline_step "Coverage thresholds (pnpm test:coverage)" "$FRONTEND_DIR" pnpm test:coverage

    if [[ "$RUN_BUILD" == true ]]; then
      if [[ -f "$FRONTEND_DIR/index.html" ]]; then
        run_pipeline_step "Production build (pnpm build in $CORE_APP)" "$CORE_APP_DIR" pnpm build
        check_file "Build output: public/frontend/index.html" "$CORE_PYTHON_DIR/public/frontend/index.html"
        check_file "Build output: www/portal.html" "$CORE_PYTHON_DIR/www/portal.html"
        check_file "Build output: public/shared-assets/icons.json" "$CORE_PYTHON_DIR/public/shared-assets/icons.json"
      else
        skip "Production build — frontend/index.html does not exist yet (portal shell not implemented)"
      fi
    fi
  fi
fi

section "Summary"
printf '  Passed:  %d\n' "$PASS_COUNT"
printf '  Missing: %d\n' "$FAIL_COUNT"
printf '  Warnings: %d\n' "$WARN_COUNT"
printf '  Skipped: %d\n' "$SKIP_COUNT"
printf '  Your work left: %d item(s), listed under "Your implementation work"\n' "$TODO_COUNT"

if (( FAIL_COUNT > 0 )); then
  printf '\nEnvironment audit found %d missing requirement(s).\n' "$FAIL_COUNT"
  exit 1
fi

if [[ "$RUN_BUILD" == true ]]; then
  printf '\nEnvironment audit passed. The production build wrote its output files; nothing was installed.\n'
elif [[ "$RUN_PIPELINE" == true ]]; then
  printf '\nEnvironment audit and pipeline run passed. Only tool caches were written; nothing was installed.\n'
else
  printf '\nEnvironment audit passed. No installation or configuration changes were made.\n'
  printf 'Run ./check-env.sh --run to also exercise the frontend pipeline.\n'
fi
exit 0
