#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Read-only audit of the TCF Frappe/Vue development container.
# This script reports missing prerequisites; it does not install or modify anything.

set -uo pipefail

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
CORE_APP="${CORE_APP:-}"
FRONTEND_DIR="${FRONTEND_DIR:-}"
PYTHON="${PYTHON:-$BENCH_DIR/env/bin/python}"

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

check_node_module() {
  local module="$1"
  if (cd "$FRONTEND_DIR" && node -e 'require.resolve(process.argv[1])' "$module" >/dev/null 2>&1); then
    ok "Frontend dependency: $module"
  else
    fail "Frontend dependency: $module"
  fi
}

check_any_node_module() {
  local label="$1" module
  shift
  for module in "$@"; do
    if (cd "$FRONTEND_DIR" && node -e 'require.resolve(process.argv[1])' "$module" >/dev/null 2>&1); then
      ok "$label — $module"
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

  mapfile -t custom_apps < <(discover_custom_apps)
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
check_file "Core app package.json (delegates to frontend)" "$BENCH_DIR/apps/$CORE_APP/package.json"
check_dir "Core Python package" "$CORE_PYTHON_DIR"
check_dir "Core backend tests" "$CORE_PYTHON_DIR/tests"

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
check_command "Corepack" corepack "--version"
if command -v pnpm >/dev/null 2>&1; then
  if output=$(COREPACK_ENABLE_NETWORK=0 pnpm --version 2>&1); then
    ok "pnpm — $(first_line "$output")"
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
  for module in \
    vue typescript vite @vitejs/plugin-vue vue-tsc pinia vue-router vue-i18n \
    sass tailwindcss vitest @vue/test-utils msw eslint eslint-plugin-vue \
    eslint-plugin-boundaries @typescript-eslint/parser @typescript-eslint/eslint-plugin \
    stylelint stylelint-config-standard-scss prettier; do
    check_node_module "$module"
  done
  check_any_node_module "DOM test environment" happy-dom jsdom
  check_any_node_module "Playwright test package" @playwright/test playwright
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
check_file "Vitest global setup" "$FRONTEND_DIR/tests/setup.ts"
check_dir "Integration tests directory" "$FRONTEND_DIR/tests/integration"
check_dir "Contract tests directory" "$FRONTEND_DIR/tests/contract"
check_dir "E2E tests directory" "$FRONTEND_DIR/tests/e2e"

section "Frontend package scripts"
check_npm_script "Vite development server script" dev
check_npm_script "Production build script" build
check_npm_script "Type-check script" typecheck type-check
check_npm_script "ESLint script" lint
check_npm_script "Stylelint script" lint:styles stylelint
check_npm_script "Unit-test script" test:unit test
check_npm_script "Integration-test script" test:integration
check_npm_script "Contract-test script" test:contract
check_npm_script "Playwright E2E script" test:e2e

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
if command -v git >/dev/null 2>&1 && git -C "$WORKSPACE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  hook_path=$(git -C "$WORKSPACE_DIR" rev-parse --git-path hooks/pre-commit 2>/dev/null || true)
  if [[ -n "$hook_path" && -x "$hook_path" ]]; then
    ok "Git pre-commit hook installed"
  else
    warn "Git pre-commit hook not installed for the workspace repository"
  fi
else
  skip "Git hook check — workspace is not a Git working tree"
fi

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

section "Summary"
printf '  Passed:  %d\n' "$PASS_COUNT"
printf '  Missing: %d\n' "$FAIL_COUNT"
printf '  Warnings:%d\n' "$WARN_COUNT"
printf '  Skipped: %d\n' "$SKIP_COUNT"

if (( FAIL_COUNT > 0 )); then
  printf '\nEnvironment audit found %d missing requirement(s).\n' "$FAIL_COUNT"
  exit 1
fi

printf '\nEnvironment audit passed. No installation or configuration changes were made.\n'
exit 0
