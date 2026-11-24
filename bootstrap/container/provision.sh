#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# bootstrap/container/provision.sh — runs INSIDE the frappe container.
# -----------------------------------------------------------------------------
# Called step by step by ./initialize.sh on the host (which shows progress,
# asks the questions and writes the log). Every step is idempotent. Values
# come from /workspace/.env, which is authoritative: the container's own
# environment may be stale.
#
#   provision.sh system-root               apt packages (run as root)
#   provision.sh system-user               uv, pre-commit and the developer
#                                          toolchain in ~/.local/bin (on PATH)
#   provision.sh wait-services             MariaDB + SeaweedFS answer
#   provision.sh wait-clamav [SECONDS]     clamd answers PING (antivirus)
#   provision.sh db-auth                   0 = root password in .env works,
#                                          3 = rejected
#   provision.sh db-root-password          ALTER root's password: old one on stdin
#   provision.sh inspect                   machine-readable bench state
#   provision.sh bench-init                bench init (when missing) + config
#   provision.sh bench-rebuild             drop sites, delete bench, bench init
#   provision.sh get-app NAME URL [REF] [custom]
#   provision.sh switch-app NAME REF       change an app's tag/branch
#   provision.sh set-origin NAME URL
#   provision.sh remove-app NAME           bench remove-app (archives the code)
#   provision.sh site-ensure SITE main|test [--force]
#   provision.sh site-config SITE main|test
#   provision.sh site-install SITE APP
#   provision.sh site-uninstall SITE APP
#   provision.sh site-migrate SITE
#   provision.sh site-password SITE
#   provision.sh site-drop SITE
#   provision.sh use-site SITE
#   provision.sh buckets                   create missing buckets, warn others
#   provision.sh build APP
#   provision.sh claude VENDORED CUSTOM CORE   install Claude Code + configs
#   provision.sh finalize                  clear caches
#
# Output lines starting with "::warn::" are shown as warnings by the host.
# -----------------------------------------------------------------------------
set -o pipefail

WS=/workspace
BENCH="$WS/frappe-bench"
RECORD="$BENCH/.frappe-dev"
TEMPLATES="$WS/bootstrap/templates"
RENDER="$WS/bootstrap/lib/render.py"
export PATH="$HOME/.local/bin:$PATH"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o StrictHostKeyChecking=accept-new}"

warn() { printf '::warn:: %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
step() { printf '\n--- %s\n' "$*"; }

# --- .env (parsed, not sourced) --------------------------------------------------
declare -A E=()
if [[ -f "$WS/.env" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
    if [[ "$v" =~ ^\'(.*)\'[[:space:]]*$ ]]; then v="${BASH_REMATCH[1]}"
    elif [[ "$v" =~ ^\"(.*)\"[[:space:]]*$ ]]; then v="${BASH_REMATCH[1]}"; fi
    E[$k]="$v"
  done < "$WS/.env"
else
  die "/workspace/.env not found — run ./setup.sh on the host."
fi
DB_USER="${E[MARIADB_ROOT_USERNAME]:-root}"
DB_PASS="${E[MARIADB_ROOT_PASSWORD]:-}"
# MariaDB 11 clients (Debian 13 and later) only ship mariadb / mariadb-admin;
# the old mysql / mysqladmin names live in an optional "compat" package.
DB_CLI="$(command -v mariadb || command -v mysql)"
DB_ADMIN="$(command -v mariadb-admin || command -v mysqladmin)"
# MariaDB >= 11.4 clients verify the server's TLS certificate by default; the
# mariadb container only has a self-signed one. Traffic stays on the private
# docker network, so verification is disabled (also globally, see system-root).
DB_TLS=(--skip-ssl-verify-server-cert)

in_bench() { cd "$BENCH" || die "frappe-bench is missing — run bench-init first."; }

record_set() {
  # record_set KIND NAME [VALUE...] — one line per KIND+NAME in $RECORD/state
  mkdir -p "$RECORD"
  local f="$RECORD/state" kind="$1" name="$2"; shift 2
  touch "$f"
  grep -v -E "^$kind $name( |$)" "$f" > "$f.tmp" || true
  [[ "${1:-}" != "--delete" ]] && printf '%s %s %s\n' "$kind" "$name" "$*" >> "$f.tmp"
  mv "$f.tmp" "$f"
}
record_get() { [[ -f "$RECORD/state" ]] && awk -v k="$1" -v n="$2" '$1 == k && $2 == n { $1 = ""; $2 = ""; sub(/^  /, ""); print; exit }' "$RECORD/state"; }

app_ref() {
  # Current tag/branch of apps/NAME: recorded ref, else git.
  local name="$1" ref
  ref=$(record_get app "$name" | awk '{print $1}')
  if [[ -z "$ref" && -d "$BENCH/apps/$name/.git" ]]; then
    ref=$(git -C "$BENCH/apps/$name" describe --tags --exact-match 2>/dev/null \
      || git -C "$BENCH/apps/$name" rev-parse --abbrev-ref HEAD 2>/dev/null)
  fi
  printf '%s' "$ref"
}

site_apps() { in_bench; bench --site "$1" list-apps 2>/dev/null | awk 'NF && $1 !~ /^[-=]/ {print $1}' | tr -d '\r'; }

new_site_scope_args() {
  if bench new-site --help 2>/dev/null | grep -q -- '--mariadb-user-host-login-scope'; then
    printf '%s\n' "--mariadb-user-host-login-scope=%"
  else
    printf '%s\n' "--no-mariadb-socket"
  fi
}

cmd="${1:-}"; shift || true
case "$cmd" in

# -----------------------------------------------------------------------------
system-root)
  [[ $EUID -eq 0 ]] || die "system-root must run as root"
  packages=(ca-certificates curl git jq iproute2 mariadb-client redis-tools unzip procps
            build-essential python3-dev libffi-dev libssl-dev libatomic1)
  missing=()
  for p in "${packages[@]}"; do
    [[ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null)" == installed ]] || missing+=("$p")
  done
  if (( ${#missing[@]} )); then
    step "installing ${missing[*]}"
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" || exit 1
  else
    echo "all container packages already installed"
  fi
  # Named volumes mounted in the bench user's home (claude-config, …) are
  # created owned by root: hand them to the bench user.
  bench_user="$(stat -c %U "$WS" 2>/dev/null)"; [[ -z "$bench_user" || "$bench_user" == UNKNOWN || "$bench_user" == root ]] && bench_user=frappe
  bench_home="$(getent passwd "$bench_user" | cut -d: -f6)"
  owned_dirs=("$bench_home/.claude")
  for d in "${owned_dirs[@]}"; do
    mkdir -p "$d"
    if [[ "$(stat -c %U "$d")" != "$bench_user" ]]; then
      chown -R "$bench_user:$bench_user" "$d"; echo "fixed ownership of $d → $bench_user"
    else
      echo "$d already owned by $bench_user"
    fi
  done
  # Operating-system libraries of Playwright's Chromium (end-to-end tests). The
  # browser itself is installed per project by the core app's `just setup`, so
  # it matches the Playwright version in its yarn.lock.
  marker=/var/lib/frappe-dev/playwright-deps.done
  if [[ -f "$marker" ]]; then
    echo "Playwright system libraries already installed"
  else
    npx_bin="$(command -v npx || ls -1 "$bench_home"/.nvm/versions/node/*/bin/npx 2>/dev/null | tail -n 1)"
    [[ -x "$npx_bin" ]] || die "npx not found: can't install Playwright's system libraries"
    step "installing Playwright's system libraries (Chromium)"
    PATH="$(dirname "$npx_bin"):$PATH" "$npx_bin" -y playwright install-deps chromium || exit 1
    mkdir -p "$(dirname "$marker")" && touch "$marker"
  fi
  # Every MariaDB client in the container (bench backups, bench mariadb, …):
  # don't verify the self-signed certificate of the mariadb container.
  mkdir -p /etc/mysql/conf.d
  cnf=/etc/mysql/conf.d/frappe-dev.cnf
  want=$'# written by frappe-dev (bootstrap/container/provision.sh)\n[client]\nskip-ssl-verify-server-cert\n'
  if [[ "$(cat "$cnf" 2>/dev/null)"$'\n' != "$want" ]]; then
    printf '%s' "$want" > "$cnf"; chmod 644 "$cnf"; echo "wrote $cnf"
  else
    echo "$cnf already present"
  fi
  ;;

# -----------------------------------------------------------------------------
system-user)
  mkdir -p "$HOME/.local/bin"
  for f in "$HOME/.bashrc" "$HOME/.profile"; do
    grep -q 'BEGIN FRAPPE-DEV PATH' "$f" 2>/dev/null || cat >> "$f" <<'EOF'
# BEGIN FRAPPE-DEV PATH
export PATH="$HOME/.local/bin:$PATH"
# END FRAPPE-DEV PATH
EOF
  done
  if ! command -v uv >/dev/null 2>&1; then
    step "installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh || exit 1
  fi
  command -v uv >/dev/null 2>&1 || die "uv is not on PATH after installation"
  # Python tools: one isolated environment each (uv tool).
  for t in pre-commit ruff mypy shellcheck-py; do
    bin="${t%-py}"
    if ! command -v "$bin" >/dev/null 2>&1; then
      step "installing $t"
      uv tool install "$t" || exit 1
    fi
  done
  # Binary releases (gitleaks, lychee, hadolint, just, trivy) into ~/.local/bin.
  # shellcheck source=bootstrap/lib/tools.sh
  source "$WS/bootstrap/lib/tools.sh"
  for t in gitleaks lychee hadolint just trivy; do
    if ! command -v "$t" >/dev/null 2>&1; then
      step "installing $t"
      tool_fetch "$t" "$HOME/.local/bin" || die "couldn't install $t"
    fi
  done
  # markdownlint-cli2 (Node): global yarn package with its binary in ~/.local/bin.
  if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
    step "installing markdownlint-cli2"
    yarn global add --silent --prefix "$HOME/.local" markdownlint-cli2 >/dev/null || die "couldn't install markdownlint-cli2"
  fi
  # This repository's git hooks (also installed on the host by install.sh).
  if [[ -d "$WS/.git" && ! -f "$WS/.git/hooks/commit-msg" ]]; then
    (cd "$WS" && pre-commit install >/dev/null) && echo "git hooks installed in /workspace"
  fi
  ver() { "$@" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1; }
  echo "uv $(ver uv --version), pre-commit $(ver pre-commit --version), ruff $(ver ruff --version)," \
    "mypy $(ver mypy --version), shellcheck $(ver shellcheck --version), gitleaks $(ver gitleaks version)," \
    "lychee $(ver lychee --version), hadolint $(ver hadolint --version), just $(ver just --version)," \
    "trivy $(ver trivy --version), markdownlint-cli2 $(ver markdownlint-cli2 --help)"
  ;;

# -----------------------------------------------------------------------------
wait-services)
  timeout="${1:-300}"; waited=0
  [[ -n "$DB_ADMIN" ]] || die "no MariaDB client in the container (mariadb-admin / mysqladmin not found)"
  echo "using $DB_ADMIN"
  # "ping" succeeds as soon as the server answers, even if the password is
  # wrong (the password is checked separately by db-auth).
  strikes=0
  until err=$("$DB_ADMIN" "${DB_TLS[@]}" ping -h mariadb --connect-timeout=3 2>&1); do
    err="${err//$'\n'/ }"
    # Only "not reachable yet" errors are worth waiting for; anything else
    # (TLS, authentication, unknown option…) won't fix itself.
    if [[ "$err" =~ Can.t\ connect|Connection\ refused|Unknown\ (server\ )?host|Lost\ connection|timed\ out|No\ route ]]; then
      strikes=0
    else
      strikes=$((strikes + 1))
      (( strikes >= 3 )) && die "MariaDB answers but the client fails: $err"
    fi
    (( waited >= timeout )) && die "MariaDB didn't answer within ${timeout}s — last error: $err"
    (( waited % 10 == 0 )) && echo "waiting for MariaDB (${waited}s): ${err:-no answer}"
    sleep 2; waited=$((waited + 2))
  done
  echo "MariaDB answers (${waited}s)"
  waited=0
  until code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://seaweedfs:8333") && [[ "$code" != 000 ]]; do
    (( waited >= timeout )) && die "SeaweedFS didn't answer within ${timeout}s"
    (( waited % 10 == 0 )) && echo "waiting for SeaweedFS (${waited}s)"
    sleep 2; waited=$((waited + 2))
  done
  echo "SeaweedFS answers (${waited}s, HTTP $code)"
  ;;

wait-clamav)
  timeout="${1:-300}"; waited=0
  host="${E[CLAMAV_HOST]:-clamav}"; port="${E[CLAMAV_PORT]:-3310}"
  # clamd protocol: "zPING\0" → "PONG\0". Answers once the signatures are loaded.
  clamd_ping() { timeout 5 bash -c "exec 3<>/dev/tcp/$host/$port && printf 'zPING\0' >&3 && head -c 4 <&3" 2>/dev/null; }
  until [[ "$(clamd_ping)" == PONG ]]; do
    (( waited >= timeout )) && die "ClamAV ($host:$port) didn't answer within ${timeout}s — check its log: docker logs <project>-clamav-1"
    (( waited % 30 == 0 )) && echo "waiting for ClamAV at $host:$port (${waited}s)"
    sleep 5; waited=$((waited + 5))
  done
  echo "ClamAV answers at $host:$port (${waited}s)"
  ;;

db-auth)
  [[ -n "$DB_CLI" ]] || die "no MariaDB client in the container (mariadb / mysql not found)"
  if "$DB_CLI" "${DB_TLS[@]}" -h mariadb -u "$DB_USER" -p"$DB_PASS" -e 'SELECT 1' >/dev/null 2>&1; then
    echo "MariaDB accepts the root password from .env"; exit 0
  fi
  echo "MariaDB rejects the root password from .env"; exit 3
  ;;

db-root-password)
  IFS= read -r old || true
  [[ -n "$old" ]] || die "old password expected on stdin"
  "$DB_CLI" "${DB_TLS[@]}" -h mariadb -u "$DB_USER" -p"$old" -e 'SELECT 1' >/dev/null 2>&1 || die "the previous password is rejected too"
  esc="${DB_PASS//\\/\\\\}"; esc="${esc//\'/\\\'}"
  "$DB_CLI" "${DB_TLS[@]}" -h mariadb -u "$DB_USER" -p"$old" -e \
    "ALTER USER IF EXISTS '$DB_USER'@'%' IDENTIFIED BY '$esc'; ALTER USER IF EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$esc'; FLUSH PRIVILEGES;" \
    || die "ALTER USER failed"
  echo "MariaDB root password updated"
  ;;

# -----------------------------------------------------------------------------
inspect)
  if [[ ! -f "$BENCH/sites/apps.txt" ]]; then
    echo "bench absent"; [[ -d "$BENCH" ]] && echo "bench-partial yes"; exit 0
  fi
  echo "bench present"
  echo "frappe $(app_ref frappe)"
  for d in "$BENCH"/apps/*/; do
    n=$(basename "$d"); [[ "$n" == frappe ]] && continue
    echo "app $n $(app_ref "$n")"
    echo "app-origin $n $(git -C "$d" remote get-url origin 2>/dev/null)"
  done
  for d in "$BENCH"/sites/*/; do
    n=$(basename "$d"); [[ -f "$d/site_config.json" ]] || continue
    apps=$(site_apps "$n" | paste -sd, -)
    if [[ -z "$apps" ]]; then echo "site-broken $n"; else echo "site $n $apps"; fi
  done
  if [[ -f "$RECORD/state" ]]; then sed 's/^/record /' "$RECORD/state"; fi
  ;;

# -----------------------------------------------------------------------------
bench-init)
  if [[ -f "$BENCH/sites/apps.txt" ]]; then
    echo "frappe-bench already initialized"
  else
    ref="${E[FRAPPE_VERSION]:-}"
    [[ -n "$ref" ]] || die "FRAPPE_VERSION is not set in .env"
    if [[ -d "$BENCH" ]]; then echo "removing an incomplete frappe-bench"; rm -rf "$BENCH"; fi
    cd "$WS" || exit 1
    step "bench init (frappe $ref)"
    bench init frappe-bench --frappe-branch "$ref" --skip-redis-config-generation --skip-assets || exit 1
    record_set app frappe "$ref" "https://github.com/frappe/frappe"
  fi
  in_bench
  bench set-config -g db_host mariadb
  bench set-config -g redis_cache redis://redis-cache:6379
  bench set-config -g redis_queue redis://redis-queue:6379
  bench set-config -g redis_socketio redis://redis-queue:6379
  # External redis containers are used: no redis processes in the Procfile.
  if grep -q '^redis' Procfile 2>/dev/null; then sed -i '/^redis/d' Procfile; echo "removed redis entries from the Procfile"; fi
  echo "bench configured"
  ;;

bench-rebuild)
  if [[ -f "$BENCH/sites/apps.txt" ]]; then
    in_bench
    for d in sites/*/; do
      n=$(basename "$d"); [[ -f "$d/site_config.json" ]] || continue
      step "dropping site $n"
      bench drop-site "$n" --root-login "$DB_USER" --root-password "$DB_PASS" --no-backup --force \
        || warn "couldn't drop site $n (its database may be left in MariaDB)"
    done
  fi
  cd "$WS" || exit 1
  step "deleting frappe-bench"
  rm -rf "$BENCH"
  exec bash "$0" bench-init
  ;;

# -----------------------------------------------------------------------------
get-app)
  name="$1"; url="$2"; ref="${3:-}"; kind="${4:-default}"
  in_bench
  if [[ -d "apps/$name" ]]; then
    echo "apps/$name already present ($(app_ref "$name"))"
  else
    step "bench get-app $name ${ref:-(default branch)}"
    args=(--skip-assets); [[ -n "$ref" ]] && args+=(--branch "$ref")
    bench get-app "${args[@]}" "$url" || exit 1
    [[ -d "apps/$name" ]] || die "bench get-app finished but apps/$name doesn't exist (is the app really called '$name'?)"
    record_set app "$name" "${ref:-default}" "$url" "$kind"
  fi
  if [[ "$kind" == custom && -f "apps/$name/.pre-commit-config.yaml" ]] && command -v pre-commit >/dev/null 2>&1; then
    (cd "apps/$name" && pre-commit install >/dev/null 2>&1 && echo "pre-commit hooks installed in apps/$name") || true
  fi
  ;;

switch-app)
  name="$1"; ref="$2"
  in_bench
  [[ -d "apps/$name/.git" ]] || die "apps/$name is not a git checkout"
  if [[ -n "$(git -C "apps/$name" status --porcelain --untracked-files=no)" ]]; then
    die "apps/$name has uncommitted changes — commit or discard them first"
  fi
  step "fetching $ref"
  if git -C "apps/$name" fetch --depth 1 origin "+refs/tags/$ref:refs/tags/$ref" 2>/dev/null; then
    git -C "apps/$name" checkout -f "refs/tags/$ref" || exit 1
  else
    git -C "apps/$name" fetch --depth 1 origin "+refs/heads/$ref:refs/remotes/origin/$ref" || die "'$ref' not found on origin"
    git -C "apps/$name" checkout -f -B "$ref" "origin/$ref" || exit 1
  fi
  step "updating requirements"
  bench setup requirements "$name" || exit 1
  url=$(record_get app "$name" | awk '{print $2}')
  kind=$(record_get app "$name" | awk '{print $3}')
  record_set app "$name" "$ref" "${url:-$(git -C "apps/$name" remote get-url origin)}" "${kind:-default}"
  echo "apps/$name is now at $ref"
  ;;

set-origin)
  name="$1"; url="$2"
  in_bench
  git -C "apps/$name" remote set-url origin "$url" || exit 1
  ref=$(app_ref "$name"); kind=$(record_get app "$name" | awk '{print $3}')
  record_set app "$name" "${ref:-default}" "$url" "${kind:-custom}"
  echo "apps/$name origin → $url"
  ;;

remove-app)
  name="$1"
  in_bench
  if [[ -d "apps/$name" ]]; then
    step "bench remove-app $name"
    bench remove-app "$name" --force || exit 1
  fi
  record_set app "$name" --delete
  echo "$name removed (code archived under frappe-bench/archived/apps)"
  ;;

# -----------------------------------------------------------------------------
site-ensure)
  site="$1"; kind="$2"; force="${3:-}"
  in_bench
  if [[ -d "sites/$site" && ! -f "sites/$site/site_config.json" ]]; then
    echo "sites/$site is incomplete — recreating it"; rm -rf "sites/$site"; force=""
  fi
  if [[ -d "sites/$site" && "$force" != "--force" ]]; then
    echo "site $site already exists"
  else
    step "bench new-site $site"
    args=(--mariadb-root-username "$DB_USER" --mariadb-root-password "$DB_PASS"
          --admin-password "${E[ADMIN_PASSWORD]}")
    mapfile -t scope < <(new_site_scope_args); args+=("${scope[@]}")
    [[ "$force" == "--force" ]] && args+=(--force)
    bench new-site "$site" "${args[@]}" || exit 1
    record_set site "$site" "$kind"
    record_set adminpw "$site" "$(printf '%s' "${E[ADMIN_PASSWORD]}" | sha256sum | cut -c1-16)"
  fi
  record_set site "$site" "$kind"
  exec bash "$0" site-config "$site" "$kind"
  ;;

site-config)
  site="$1"; kind="$2"
  in_bench
  [[ -f "sites/$site/site_config.json" ]] || die "sites/$site/site_config.json not found"
  meet=0; for a in ${E[DEFAULT_APPS]:-}; do
    grep -qE "^$a\|[^|]*\|[^|]*\|[^|]*sfu" "$TEMPLATES/apps.catalog" && meet=1
  done
  dev="${E[MAIN_SITE_DEVELOPER_MODE]:-0}"; [[ "$dev" == 1 ]] || dev=0
  clam_port="${E[CLAMAV_PORT]:-3310}"; [[ "$clam_port" =~ ^[0-9]+$ ]] || clam_port=3310
  fragment=$(mktemp)
  # Values land inside JSON strings: escape quotes and backslashes.
  jesc() { local v="${1//\\/\\\\}"; printf '%s' "${v//\"/\\\"}"; }
  printf '%s\0' \
    "SITE_NAME=$site" "DEVELOPER_MODE=$dev" "MEET_ENABLED=$meet" \
    "SEAWEEDFS_ENDPOINT=$(jesc "${E[SEAWEEDFS_ENDPOINT]:-http://seaweedfs:8333}")" \
    "SEAWEEDFS_ACCESS_KEY=$(jesc "${E[SEAWEEDFS_ACCESS_KEY]:-}")" "SEAWEEDFS_SECRET_KEY=$(jesc "${E[SEAWEEDFS_SECRET_KEY]:-}")" \
    "JWT_SECRET=$(jesc "${E[JWT_SECRET]:-}")" "MEET_ANNOUNCED_IP=$(jesc "${E[WEBRTC_ANNOUNCED_IP]:-}")" \
    "CLAMAV_HOST=$(jesc "${E[CLAMAV_HOST]:-clamav}")" "CLAMAV_PORT=$clam_port" \
    | python3 "$RENDER" "$TEMPLATES/site-config/$kind.json.template" "$fragment" >/dev/null || exit 1
  python3 - "sites/$site/site_config.json" "$fragment" <<'PY' || exit 1
import json, sys, os
target, fragment = sys.argv[1], sys.argv[2]
with open(fragment) as f:
    extra = json.load(f)
with open(target) as f:
    conf = json.load(f)
changed = [k for k, v in extra.items() if conf.get(k) != v]
conf.update(extra)
tmp = target + ".tmp"
with open(tmp, "w") as f:
    json.dump(conf, f, indent=1, sort_keys=True)
    f.write("\n")
os.replace(tmp, target)
print("site_config.json: " + (", ".join(changed) + " updated" if changed else "already up to date"))
PY
  rm -f "$fragment"
  ;;

site-install)
  site="$1"; app="$2"
  if site_apps "$site" | grep -qx "$app"; then echo "$app already installed on $site"; exit 0; fi
  in_bench
  step "bench --site $site install-app $app"
  bench --site "$site" install-app "$app"
  ;;

site-uninstall)
  site="$1"; app="$2"
  site_apps "$site" | grep -qx "$app" || { echo "$app is not installed on $site"; exit 0; }
  in_bench
  bench --site "$site" uninstall-app "$app" --yes --no-backup --force
  ;;

site-migrate)
  in_bench; bench --site "$1" migrate ;;

site-password)
  site="$1"; in_bench
  bench --site "$site" set-admin-password "${E[ADMIN_PASSWORD]}" || exit 1
  record_set adminpw "$site" "$(printf '%s' "${E[ADMIN_PASSWORD]}" | sha256sum | cut -c1-16)"
  echo "Administrator password updated on $site"
  ;;

site-drop)
  site="$1"; in_bench
  bench drop-site "$site" --root-login "$DB_USER" --root-password "$DB_PASS" --no-backup --force || exit 1
  record_set site "$site" --delete; record_set adminpw "$site" --delete
  ;;

use-site)
  in_bench; bench use "$1" ;;

# -----------------------------------------------------------------------------
buckets)
  command -v uv >/dev/null 2>&1 || die "uv missing — run system-user first"
  SEAWEEDFS_ENDPOINT="${E[SEAWEEDFS_ENDPOINT]:-http://seaweedfs:8333}" \
  SEAWEEDFS_ACCESS_KEY="${E[SEAWEEDFS_ACCESS_KEY]:-}" SEAWEEDFS_SECRET_KEY="${E[SEAWEEDFS_SECRET_KEY]:-}" \
  BUCKETS="${E[SEAWEEDFS_BUCKETS]:-}" \
  uv run --quiet --no-project --with boto3 python3 - <<'PY'
import os
import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3", endpoint_url=os.environ["SEAWEEDFS_ENDPOINT"],
                  aws_access_key_id=os.environ["SEAWEEDFS_ACCESS_KEY"] or "anonymous",
                  aws_secret_access_key=os.environ["SEAWEEDFS_SECRET_KEY"] or "anonymous",
                  region_name="us-east-1")
wanted = os.environ.get("BUCKETS", "").split()
existing = {b["Name"] for b in s3.list_buckets().get("Buckets", [])}
for name in wanted:
    if name in existing:
        print(f"bucket {name}: already exists")
    else:
        s3.create_bucket(Bucket=name)
        print(f"bucket {name}: created")
for name in sorted(existing - set(wanted)):
    print(f"::warn:: bucket '{name}' exists in SeaweedFS but is not listed in SEAWEEDFS_BUCKETS — left untouched")
PY
  ;;

# -----------------------------------------------------------------------------
build)
  app="$1"; in_bench
  bench build --app "$app"
  ;;

claude)
  vendored="$1"; custom="$2"; core="$3"
  mkdir -p "$HOME/.local/bin"
  if command -v claude >/dev/null 2>&1; then
    echo "Claude Code already installed ($(claude --version 2>/dev/null))"
  else
    step "installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash || exit 1
  fi
  in_bench
  mkdir -p .claude
  deny=""; for a in frappe $vendored; do
    deny+="      \"Edit(apps/$a/**)\","$'\n'"      \"Write(apps/$a/**)\","$'\n'
  done
  excludes=""; for a in frappe $vendored; do excludes+="apps/$a "; done
  vlist=""; for a in frappe $vendored; do vlist+="\`apps/$a\`, "; done
  clist=""; for a in $custom; do clist+="\`apps/$a\`, "; done
  printf '%s\0' "VENDORED_DENY_JSON=${deny%$'\n'}" \
    | python3 "$RENDER" "$TEMPLATES/claude/settings.json.template" .claude/settings.json || exit 1
  printf '%s\0' "SITE_NAME=${E[SITE_NAME]}" "TEST_SITE_NAME=${E[TEST_SITE_NAME]}" \
    "TEST_MINIMAL_SITE_NAME=${E[TEST_MINIMAL_SITE_NAME]:-test-minimal.${E[SITE_NAME]}}" \
    "VENDORED_APPS=${vlist%, }" "CUSTOM_APPS=${clist%, }" "CORE_APP=${core:-none}" \
    "VENDORED_EXCLUDES=${excludes% }" \
    | python3 "$RENDER" "$TEMPLATES/claude/CLAUDE.md.template" CLAUDE.md || exit 1
  ;;

finalize)
  in_bench
  for d in sites/*/; do
    n=$(basename "$d"); [[ -f "$d/site_config.json" ]] || continue
    bench --site "$n" clear-cache || warn "clear-cache failed on $n"
  done
  ;;

*)
  sed -n '2,40p' "$0"; exit 2 ;;
esac
