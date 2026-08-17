#!/bin/bash
set -e

# Work relative to this script's location, so it behaves the same regardless
# of the caller's current directory.
cd "$(dirname "$0")"

bash bootstrap/setup-git.sh

if [ ! -f .env ]; then
  bash bootstrap/setup-env.sh
fi

touch bootstrap/.bootstrap.log

source .env

if [ ! -f .devcontainer/devcontainer.json ]; then
  cp .devcontainer/devcontainer.json.template .devcontainer/devcontainer.json
  sed -i -n "s/__MARIADB_ROOT_PASSWORD__/${MARIADB_ROOT_PASSWORD}/" .devcontainer/devcontainer.json
  sed -i -n "s/__MARIADB_ROOT_USERNAME__/${MARIADB_ROOT_USERNAME}/" .devcontainer/devcontainer.json
fi

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

echo ""
echo "Pulling images and starting containers (mariadb, redis-cache, redis-queue, seaweedfs, frappe)..."
$DOCKER_COMPOSE up -d

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
         192.168.0.210   tcf.local
  2. Open this folder in VS Code (Remote-SSH into this VM), then run
     "Dev Containers: Attach to Running Container..." and pick "frappe".
  3. First attach only: run "Dev Containers: Open Container Configuration
     File" and copy in the extensions/settings from
     .devcontainer/devcontainer.json — VS Code remembers this per
     container name from then on, so you only do it once, ever.

Site:      http://tcf.local:8000  (user: Administrator, password: see
           ADMIN_PASSWORD in .env)
MariaDB:   192.168.0.210:3306 (e.g. for DBeaver — root / see .env)

Day to day:
  ./shutdown.sh   — stop containers safely at the end of a session
  ./startup.sh    — bring them back up after a manual stop or reboot
=====================================================================
EOF