#!/bin/bash
set -e

cd "$(dirname "$0")"
source bootstrap/lib.sh

require_env_file

case "$DOCKER_STATUS" in
  1)
    echo "Docker isn't installed on this machine."
    echo "Run ./install.sh first — it installs Docker as part of first-time setup."
    exit 1
    ;;
  2)
    echo "Docker is installed but the daemon doesn't seem to be running."
    if confirm "Start the Docker service now (sudo systemctl start docker)?"; then
      sudo systemctl start docker
      source bootstrap/lib.sh
      if [ "$DOCKER_STATUS" != "0" ]; then
        echo "Docker still isn't reachable after starting the service — aborting."
        exit 1
      fi
    else
      echo "Can't continue without Docker running. Aborting."
      exit 1
    fi
    ;;
esac

# compose's own "up -d" is already idempotent (already-running containers are
# left alone), so there's no need to pre-check state ourselves — that check
# turned out to be unreliable across docker compose versions.
echo "Starting containers..."
$DOCKER_COMPOSE up -d

echo ""
bash bootstrap/setup-vscode.sh

echo ""
echo "Waiting for MariaDB..."
load_env
WAITED=0
until $DOCKER_COMPOSE exec -T mariadb mysqladmin ping \
    -u "${MARIADB_ROOT_USERNAME:-root}" -p"${MARIADB_ROOT_PASSWORD}" --silent 2>/dev/null; do
  WAITED=$((WAITED + 2))
  if [ "$WAITED" -ge 120 ]; then
    echo "MariaDB didn't come up within 120s. Check 'docker compose logs mariadb'."
    exit 1
  fi
  sleep 2
done
echo "MariaDB is ready."

# Safety net: if a previous --volumes / --all shutdown (or anything else)
# left frappe-bench in an incomplete or missing state, offer to reprovision
# rather than silently leaving a broken environment.
if ! $DOCKER_COMPOSE exec -T frappe test -f frappe-bench/sites/apps.txt 2>/dev/null; then
  echo ""
  echo "frappe-bench doesn't look fully provisioned inside the frappe container"
  echo "(expected after a --volumes or --all shutdown, or on a very first run"
  echo "if you're using startup.sh instead of install.sh)."
  if confirm "Run bench provisioning now (bootstrap/setup-bench.sh)?"; then
    $DOCKER_COMPOSE exec frappe ./bootstrap/setup-bench.sh
  else
    echo "Skipping. Run it manually later with:"
    echo "  docker compose -f .devcontainer/docker-compose.yml exec frappe ./bootstrap/setup-bench.sh"
  fi
fi

echo ""
echo "Containers are up. Open this folder in VS Code and 'Attach to Running Container' (frappe) to start coding."