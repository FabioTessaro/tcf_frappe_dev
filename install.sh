#!/bin/bash
set -e

# Work relative to this script's location, so it behaves the same regardless
# of the caller's current directory.
cd "$(dirname "$0")"

usage() {
  cat << EOF
Usage: ./install.sh [mode]

Modes:
  --attach   (default) Set up for VS Code's "Attach to Running Container":
             installs Docker if missing, pulls and starts the 5 containers,
             pre-seeds the VS Code Server build inside frappe (works around
             a Docker Engine bug — see bootstrap/setup-vscode.sh), and runs
             first-time bench provisioning inside the frappe container.
  --reopen   Set up for VS Code's "Reopen in Container" instead: only
             (re)generates .devcontainer/devcontainer.json. Building the
             container, installing the VS Code Server inside it, and bench
             provisioning are then handled by VS Code itself — this mode
             does not start containers or touch the frappe container.
EOF
}

MODE="attach"
case "${1:-}" in
  ""|--attach) MODE="attach" ;;
  --reopen) MODE="reopen" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown option: $1"; usage; exit 1 ;;
esac

bash bootstrap/setup-git.sh

if [ ! -f .env ]; then
  bash bootstrap/setup-env.sh
fi

# touch bootstrap/.bootstrap.log

bash bootstrap/setup-devcontainer.sh

# Docker itself is a prerequisite for BOTH modes — "Reopen in Container"
# still needs it on the VM to build/start anything — so this check and the
# boot-enable below are not gated behind --attach/--reopen.
if ! command -v docker &> /dev/null; then
  echo "Docker not found — installing..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  echo "Added $USER to the docker group. That doesn't take effect in the"
  echo "current shell until you log out/in (or run 'newgrp docker') — this"
  echo "script keeps going via sudo, so this run itself isn't blocked."
fi

# Make sure the Docker daemon itself is enabled to start on boot, so the
# containers (which get their own restart policy below) can come back up
# automatically after a VM reboot without any manual step. get.docker.com
# usually already enables this, but we don't rely on that assumption —
# running it again is harmless either way.
sudo systemctl enable docker.service containerd.service > /dev/null 2>&1 || true

# From this point on, use the shared docker/compose wrapper so this script
# behaves consistently with shutdown.sh and startup.sh (sudo-or-not is
# detected once, in lib.sh).
source bootstrap/lib.sh

if [ "$MODE" == "reopen" ]; then
  cat << EOF

=====================================================================
Install complete for "Reopen in Container" mode. Nothing was started —
.devcontainer/devcontainer.json is ready and VS Code builds/starts the
container itself.

Note: postCreateCommand and the extensions list in devcontainer.json
are still placeholders (open item, not yet wired up), so bench
provisioning won't run automatically after the first "Reopen in
Container" yet. Until that's in place, run this once from a terminal
inside the container afterward:
    ./bootstrap/setup-bench.sh

Next steps:
  1. On whichever machine you'll browse FROM (this VM or your own laptop),
     add this to its hosts file so tcf.local resolves:
         <remote-host-ip>   tcf.local
  2. Open this folder in VS Code (Remote-SSH into this VM), then run
     "Dev Containers: Reopen in Container".

Site:      http://tcf.local:8000  (user: Administrator, password: see
           ADMIN_PASSWORD in .env)
MariaDB:   <remote-host-ip>:3306 (e.g. for DBeaver — root / see .env)

Day to day:
  ./shutdown.sh   — stop containers safely at the end of a session
  ./startup.sh    — bring them back up after a manual stop or reboot
=====================================================================
EOF
  exit 0
fi

echo ""
echo "Pulling images and starting containers (mariadb, redis-cache, redis-queue, seaweedfs, frappe)..."
$DOCKER_COMPOSE up -d

echo ""
bash bootstrap/setup-vscode.sh

echo ""
echo "Running first-time bench provisioning inside the frappe container (this can take a while on a fresh install)..."
$DOCKER_COMPOSE exec frappe ./bootstrap/setup-bench.sh

cat << EOF

=====================================================================
Install complete. Containers are running with a "restart: unless-stopped"
policy, so they'll come back up automatically after a Docker/VM restart —
no need to re-run this script unless you deliberately tear things down.

Next steps:
  1. On whichever machine you'll browse FROM (this VM or your own laptop),
     add this to its hosts file so tcf.local resolves:
         <remote-host-ip>   tcf.local
  2. Open this folder in VS Code (Remote-SSH into this VM), then run
     "Dev Containers: Attach to Running Container..." and pick "frappe".
  3. First attach only: run "Dev Containers: Open Container Configuration
     File" and copy in the extensions/settings from
     .devcontainer/devcontainer.json — VS Code remembers this per
     container name from then on, so you only do it once, ever.

Site:      http://tcf.local:8000  (user: Administrator, password: see
           ADMIN_PASSWORD in .env)
MariaDB:   <remote-host-ip>:3306 (e.g. for DBeaver — root / see .env)

Day to day:
  ./shutdown.sh   — stop containers safely at the end of a session
  ./startup.sh    — bring them back up after a manual stop or reboot
=====================================================================
EOF