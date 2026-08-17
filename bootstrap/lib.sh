#!/bin/bash
# Shared helpers for install.sh / shutdown.sh / startup.sh.
# This file is meant to be sourced ("source bootstrap/lib.sh"), not executed
# directly — it has no shebang effect of its own and defines variables/
# functions in the caller's shell.

# Resolve paths relative to THIS file, not the caller's $PWD, so every
# top-level script works the same whether it's run as ./install.sh,
# bash install.sh, or via an absolute path.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$LIB_DIR")"

COMPOSE_FILE="$REPO_ROOT/.devcontainer/docker-compose.yml"
ENV_FILE="$REPO_ROOT/.env"

# --- Decide whether docker commands need a "sudo" prefix. ------------------
# On a brand-new install, install.sh may add the user to the "docker" group,
# but that membership doesn't apply until the user logs out/in again — so a
# later shutdown.sh/startup.sh run in a *fresh* terminal might still need
# sudo, even though a terminal that was already open (like the one running
# install.sh) does not. Rather than assume either way, we just test it.
#
# Sets:
#   DOCKER         "docker" or "sudo docker" (word-split on use, intentionally)
#   DOCKER_STATUS  0 = daemon reachable, 1 = docker not installed,
#                  2 = docker installed but daemon unreachable even with sudo
detect_docker() {
  if ! command -v docker &> /dev/null; then
    DOCKER=""
    return 1
  fi

  if docker info &> /dev/null; then
    DOCKER="docker"
    return 0
  fi

  if sudo docker info &> /dev/null; then
    # DOCKER="sudo docker"
    DOCKER="sudo --preserve-env=HOME docker"
    return 0
  fi

  # Docker is installed but nothing can reach the daemon — most likely the
  # docker service itself isn't running. Still prefer "sudo docker" as the
  # best guess for whoever wants to try starting the service next.
  DOCKER="sudo docker"
  return 2
}

detect_docker
DOCKER_STATUS=$?

# Word-splits intentionally when used unquoted (e.g. $DOCKER_COMPOSE up -d),
# so DOCKER being "sudo docker" works as two separate argv entries.
DOCKER_COMPOSE="$DOCKER compose -f $COMPOSE_FILE --env-file $ENV_FILE"

# --- .env helpers ------------------------------------------------------------
require_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "No .env file found at $ENV_FILE."
    echo "Run ./install.sh first — it creates .env as part of first-time setup."
    exit 1
  fi
}

# Exports every key from .env into the current shell (e.g. so a script can
# read $MARIADB_ROOT_PASSWORD the same way docker compose's env_file does).
load_env() {
  require_env_file
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
}

# --- Confirmation prompts ---------------------------------------------------
# confirm "question" — returns success (0) only on y/yes.
confirm() {
  local reply
  read -r -p "$1 [y/N]: " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# confirm_typed "question" "PHRASE" — returns success only if the user types
# PHRASE exactly. Used for destructive actions where a plain y/N is too easy
# to hit by accident (e.g. wiping volumes).
confirm_typed() {
  local reply
  read -r -p "$1 (type '$2' to confirm): " reply
  [ "$reply" == "$2" ]
}