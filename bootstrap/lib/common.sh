#!/usr/bin/env bash
# shellcheck disable=SC2034
# -----------------------------------------------------------------------------
# bootstrap/lib/common.sh — shared foundation of the host-side root scripts.
# -----------------------------------------------------------------------------
# Source it first thing:   source "$(dirname "$0")/bootstrap/lib/common.sh"
# then call:                script_init <name> "$@"
#
# Provides: repository paths, settings.conf, logging + UI (log.sh / ui.sh),
# .env parsing/writing, template rendering, docker / compose wrappers, sudo
# helpers and common validators. Nothing here changes the system on import.
# -----------------------------------------------------------------------------

LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(dirname "$LIB_DIR")"
REPO_ROOT="$(dirname "$BOOTSTRAP_DIR")"
TEMPLATE_DIR="$BOOTSTRAP_DIR/templates"
SETTINGS_FILE="$BOOTSTRAP_DIR/settings.conf"

ENV_FILE="$REPO_ROOT/.env"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
BENCH_DIR="$REPO_ROOT/frappe-bench"
LOG_DIR="$REPO_ROOT/logs"
STATE_DIR="$REPO_ROOT/.state"
STATE_TMP_DIR="$STATE_DIR/tmp"
BACKUP_DIR="$STATE_DIR/backups"
SNAPSHOT_FILE="$STATE_DIR/initialized.env"
VSCODE_DIR="$REPO_ROOT/.vscode"

# Inside the container the repository is mounted here.
CONTAINER_WORKSPACE=/workspace

# --- settings.conf (parsed, never executed) ----------------------------------
settings_load() {
  COMPOSE_PROJECT_NAME="tcf-frappe-dev"; LOG_KEEP=5; SERVICE_WAIT_TIMEOUT=300
  CONTAINER_USER=frappe; CONTAINER_HOME=/home/frappe; VERSION_PICKER_LIMIT=15
  [[ -f "$SETTINGS_FILE" ]] || return 0
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    value="${value%$'\r'}"; value="${value#\"}"; value="${value%\"}"; value="${value#\'}"; value="${value%\'}"
    case "$key" in
      COMPOSE_PROJECT_NAME|LOG_KEEP|SERVICE_WAIT_TIMEOUT|CONTAINER_USER|CONTAINER_HOME|VERSION_PICKER_LIMIT)
        printf -v "$key" '%s' "$value" ;;
    esac
  done < "$SETTINGS_FILE"
}
settings_load

# shellcheck source=bootstrap/lib/log.sh
source "$LIB_DIR/log.sh"
# shellcheck source=bootstrap/lib/ui.sh
source "$LIB_DIR/ui.sh"

# --- script lifecycle -----------------------------------------------------------
_SUDO_KEEPALIVE_PID=""
_TTY_STATE=""

# Terminal settings are saved at start and restored on every exit: menus and
# password prompts switch the terminal to "no echo / single key" mode, and an
# exit in the middle of such a read (Ctrl+C) would otherwise leave it there.
_tty_save() {
  [[ "$UI_TTY_IN" == true ]] || return 0
  _TTY_STATE=$(stty -g < /dev/tty 2>/dev/null) || _TTY_STATE=""
}
_tty_restore() {
  [[ -n "$_TTY_STATE" ]] && stty "$_TTY_STATE" < /dev/tty 2>/dev/null
  _ui_cursor_show
  return 0
}

_script_exit() {
  local rc=$?
  trap - EXIT
  _tty_restore
  [[ -n "$_SUDO_KEEPALIVE_PID" ]] && kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null
  [[ -n "$UI_LAST_OUTPUT" && -f "$UI_LAST_OUTPUT" ]] && rm -f "$UI_LAST_OUTPUT"
  [[ "$STATE_TMP_DIR" == "$STATE_DIR/tmp/run-"* ]] && rm -rf "$STATE_TMP_DIR"
  log_line "exit status $rc"
  if [[ "${SCRIPT_SUMMARY:-true}" == true ]]; then ui_summary "$rc"; fi
  exit "$rc"
}

_script_interrupt() {
  _tty_restore
  printf '\n'
  ui_warn "Interrupted by the user."
  exit 130
}

# script_init NAME "$@" — banner, log file, traps. Handles the flags shared
# by every script (--trace, --no-color) and leaves the rest in SCRIPT_ARGS.
SCRIPT_ARGS=()
SCRIPT_TRACE=false
script_init() {
  local name="$1"; shift
  SCRIPT_NAME="$name"
  SCRIPT_ARGS=()
  local a
  for a in "$@"; do
    case "$a" in
      --trace) SCRIPT_TRACE=true ;;
      *) SCRIPT_ARGS+=("$a") ;;
    esac
  done
  cd "$REPO_ROOT" || exit 1
  STATE_TMP_DIR="$STATE_DIR/tmp/run-$$"
  mkdir -p "$STATE_DIR" "$STATE_TMP_DIR"
  chmod 700 "$STATE_DIR" 2>/dev/null || true
  log_init "$name" "$@"
  _tty_save
  trap _script_exit EXIT
  trap _script_interrupt INT TERM
  [[ "$SCRIPT_TRACE" == true ]] && log_trace_on
  return 0
}

# --- sudo -----------------------------------------------------------------------
# sudo_prime REASON — ask for the sudo password once (visibly, not under a
# spinner) and keep the credential fresh until the script ends.
sudo_prime() {
  if [[ $EUID -eq 0 ]]; then SUDO=(); return 0; fi
  SUDO=(sudo)
  if sudo -n true 2>/dev/null; then :
  else
    ui_info "Administrator rights are needed to ${1:-continue}."
    ui_require_tty "the sudo password"
    sudo -v || ui_die "sudo authentication failed."
  fi
  if [[ -z "$_SUDO_KEEPALIVE_PID" ]]; then
    ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    _SUDO_KEEPALIVE_PID=$!
  fi
}
SUDO=(sudo)

# --- validators (return 0 when valid) -------------------------------------------
valid_app_name()   { [[ "$1" =~ ^[a-z][a-z0-9_]*$ ]]; }
valid_hostname()   { [[ ${#1} -le 253 && "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$ ]]; }
valid_site_name()  { valid_hostname "$1" && [[ "$1" != test.* && "$1" != test-minimal.* ]]; }
valid_bucket()     { [[ "$1" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; }
valid_commit()     { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
valid_ipv4()       { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
valid_ip_or_host() { valid_ipv4 "$1" || valid_hostname "$1"; }
valid_env_value()  { [[ "$1" != *"'"* && "$1" != *$'\n'* && "$1" != *$'\r'* ]]; }
# Secrets: the only hard rule is what .env can store (values are written
# inside single quotes): no single quote, no line breaks.
valid_secret() { [[ -n "$1" ]] && valid_env_value "$1"; }
# secret_weakness VALUE — prints why VALUE is weak (empty when fine).
secret_weakness() {
  local r=()
  (( ${#1} < 8 )) && r+=("shorter than 8 characters")
  [[ "$1" == *[[:space:]]* ]] && r+=("contains spaces")
  if (( ${#r[@]} == 2 )); then printf 'This value is %s and %s.' "${r[0]}" "${r[1]}"
  elif (( ${#r[@]} == 1 )); then printf 'This value is %s.' "${r[0]}"; fi
  return 0
}
valid_git_url()    { [[ "$1" =~ ^(git@[^:]+:.+|ssh://.+|https://.+|file://.+)$ ]] && [[ "$1" != *[[:space:]]* ]]; }
valid_git_prefix() { [[ "$1" =~ ^(git@[^:]+:.*|ssh://.+|https://.+)$ ]] && [[ "$1" != */ && "$1" != *[[:space:]]* ]]; }

gen_password() { openssl rand -hex 16; }
gen_key()      { openssl rand -hex 24; }

# --- .env ---------------------------------------------------------------------
# env_parse FILE ARRAY — loads KEY=VALUE lines into the associative array
# named ARRAY. The file is parsed, never sourced. Quotes are removed.
env_parse() {
  local file="$1"
  local -n _dst="$2"
  _dst=()
  [[ -f "$file" ]] || return 1
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[2]}"; value="${BASH_REMATCH[3]}"
    if [[ "$value" =~ ^\'(.*)\'[[:space:]]*$ ]]; then value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^\"(.*)\"[[:space:]]*$ ]]; then value="${BASH_REMATCH[1]}"
    else value="${value%%[[:space:]]#*}"; value="${value%"${value##*[![:space:]]}"}"
    fi
    _dst["$key"]="$value"
  done < "$file"
  return 0
}

# Global configuration loaded from .env.
declare -gA ENV=()

env_require() {
  if [[ ! -f "$ENV_FILE" ]]; then
    ui_die "No .env file found in $REPO_ROOT." \
      "The project isn't configured yet: run ./setup.sh first, then run this script again."
  fi
  env_parse "$ENV_FILE" ENV
  local k
  for k in ADMIN_PASSWORD MARIADB_ROOT_PASSWORD SEAWEEDFS_ACCESS_KEY SEAWEEDFS_SECRET_KEY JWT_SECRET; do
    [[ -n "${ENV[$k]:-}" ]] && log_add_secret "${ENV[$k]}"
  done
  log_line "loaded .env ($(wc -l < "$ENV_FILE") lines)"
}

# env_set_key KEY VALUE — set one key in .env (replaced in place, or appended),
# keeping its mode. For keys owned by other scripts than setup.sh
# (PLATFORM_URL); setup.sh keeps them when it rewrites the file.
env_set_key() {
  local key="$1" value="$2" tmp
  [[ -f "$ENV_FILE" ]] || return 1
  valid_env_value "$value" || return 1
  tmp=$(mktemp "$STATE_TMP_DIR/env.XXXXXX") || return 1
  python3 - "$ENV_FILE" "$tmp" "$key" "$(env_quote "$value")" <<'PY' || { rm -f "$tmp"; return 1; }
import re, sys
src, dst, key, value = sys.argv[1:]
lines = open(src, encoding="utf-8").read().splitlines()
pat = re.compile(rf"^\s*{re.escape(key)}=")
out, done = [], False
for line in lines:
    if pat.match(line):
        if not done:
            out.append(f"{key}={value}")
            done = True
        continue
    out.append(line)
if not done:
    out.append(f"{key}={value}")
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
  cat "$tmp" > "$ENV_FILE" && rm -f "$tmp"
  log_line "env_set_key $key"
}

# env_quote VALUE — single-quoted .env value (values never contain ').
env_quote() { printf "'%s'" "$1"; }

# --- templates ------------------------------------------------------------------
# render TEMPLATE TARGET [--mode 600] [--backup-dir DIR] [--check] -- KEY=VALUE...
# The values travel to render.py on stdin (NUL separated), never on argv.
render() {
  local template="$1" target="$2"; shift 2
  local opts=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do opts+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  command -v python3 >/dev/null 2>&1 || ui_die "python3 is required to render templates (run ./install.sh)."
  local out rc=0
  out=$(printf '%s\0' "$@" | python3 "$LIB_DIR/render.py" "$template" "$target" "${opts[@]}" 2>&1) || rc=$?
  log_line "render ${template#"$REPO_ROOT"/} -> ${target#"$REPO_ROOT"/}: $out (rc=$rc)"
  RENDER_STATUS="${out%%:*}"
  if (( rc != 0 && rc != 3 )); then ui_error "Template rendering failed: $out"; fi
  return "$rc"
}

# --- docker -----------------------------------------------------------------------
# docker_detect — sets DOCKER (array) and DOCKER_STATUS:
#   0 reachable, 1 not installed, 2 installed but daemon unreachable.
DOCKER=(docker)
DOCKER_STATUS=1
docker_detect() {
  if ! command -v docker >/dev/null 2>&1; then DOCKER=(); DOCKER_STATUS=1; return 1; fi
  if docker info >/dev/null 2>&1; then DOCKER=(docker); DOCKER_STATUS=0; return 0; fi
  if sudo -n docker info >/dev/null 2>&1; then
    DOCKER=(sudo --preserve-env=HOME docker); DOCKER_STATUS=0
    sudo_prime "use Docker"   # keeps the credential alive during long steps
    return 0
  fi
  if [[ "$UI_TTY_IN" == true ]] && id -nG 2>/dev/null | grep -qvw docker; then
    # Not in the docker group yet (fresh install, no re-login): try sudo.
    ui_note "Your user can't reach Docker directly (not in the docker group yet — log out and in again?) — using sudo."
    sudo_prime "use Docker"
    if sudo docker info >/dev/null 2>&1; then DOCKER=(sudo --preserve-env=HOME docker); DOCKER_STATUS=0; return 0; fi
  fi
  DOCKER=(sudo docker); DOCKER_STATUS=2; return 2
}

# docker_require — docker_detect or exit with a helpful message.
docker_require() {
  docker_detect
  case "$DOCKER_STATUS" in
    0) log_line "docker command: ${DOCKER[*]}" ;;
    1) ui_die "Docker is not installed." "Run ./install.sh first." ;;
    2) ui_die "Docker is installed but the daemon isn't reachable." \
         "Start it with: sudo systemctl start docker   (or re-run ./install.sh)" ;;
  esac
}

dk() { "${DOCKER[@]}" "$@"; }

# dc ARGS — docker compose for this project (requires the generated file).
dc() {
  "${DOCKER[@]}" compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" --project-directory "$REPO_ROOT" "$@"
}

# project_containers [--running] — IDs of this project's containers, found by
# compose label so it works even when docker-compose.yml was deleted.
project_containers() {
  local filter=(--filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME")
  if [[ "${1:-}" == "--running" ]]; then dk ps -q "${filter[@]}"; else dk ps -aq "${filter[@]}"; fi
}

project_running_services() {
  dk ps --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" \
    --format '{{.Label "com.docker.compose.service"}}' 2>/dev/null | sort -u
}

frappe_running() {
  [[ -f "$COMPOSE_FILE" ]] || return 1
  dc exec -T frappe true >/dev/null 2>&1
}

# cx ARGS — run a command in the frappe container as the bench user.
cx() { dc exec -T -u "$CONTAINER_USER" -w "$CONTAINER_WORKSPACE" frappe "$@"; }
# cx_root ARGS — same, as root.
cx_root() { dc exec -T -u root frappe "$@"; }

# in_dev_container — true when this script runs inside the frappe container
# (where the repository is mounted at $CONTAINER_WORKSPACE).
in_dev_container() { [[ -f /.dockerenv && "$REPO_ROOT" == "$CONTAINER_WORKSPACE" ]]; }

# provision STEP ARGS — run bootstrap/container/provision.sh inside the
# container (directly when this script already runs there).
provision() {
  if in_dev_container; then bash "$REPO_ROOT/bootstrap/container/provision.sh" "$@"
  else cx bash "$CONTAINER_WORKSPACE/bootstrap/container/provision.sh" "$@"; fi
}

# dev_run DIR CMD... — run CMD in DIR (a path under the repository) as the
# bench user inside the frappe container, directly when already there.
dev_run() {
  local dir="$1"; shift
  if in_dev_container; then (cd "$dir" && "$@"); return; fi
  dc exec -T -u "$CONTAINER_USER" -w "$CONTAINER_WORKSPACE${dir#"$REPO_ROOT"}" frappe \
    bash -c 'export PATH="$HOME/.local/bin:$PATH"; exec "$@"' _ "$@"
}

# gh_container_login — log the frappe container's GitHub CLI in with the host's
# token (host only). The token travels on stdin, never on a command line.
gh_container_login() {
  in_dev_container && return 0
  local token
  token=$(gh auth token 2>/dev/null) && [[ -n "$token" ]] || { echo "gh is not logged in on the host" >&2; return 1; }
  printf '%s\n' "$token" | dc exec -T -u "$CONTAINER_USER" frappe bash -c \
    'export PATH="$HOME/.local/bin:$PATH"; gh auth login --hostname github.com --git-protocol ssh --with-token && gh auth status --hostname github.com'
}

# --- misc -----------------------------------------------------------------------
contains() { local n="$1" x; shift; for x in "$@"; do [[ "$x" == "$n" ]] && return 0; done; return 1; }

# join SEP ITEMS...
join() { local IFS="$1"; shift; printf '%s' "$*"; }

detect_lan_ip() {
  local ip
  ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
  [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  printf '%s' "$ip"
}

# usage_from_header FILE — prints the comment block at the top of a script
# (lines starting with "#", after the shebang) as its --help text.
usage_from_header() {
  awk 'NR == 1 && /^#!/ { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$1"
}
