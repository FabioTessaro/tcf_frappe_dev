#!/bin/bash
set -e

bash bootstrap/setup-git.sh

if [ ! -f .env ]; then
  bash bootstrap/setup-env.sh
fi

touch bootstrap/.bootstrap.log

if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
  echo "Added $USER to docker group — log out and back in (or run 'newgrp docker') before continuing."
fi

sudo docker compose -f .devcontainer/docker-compose.yml --env-file .env up -d

sudo docker compose -f .devcontainer/docker-compose.yml exec frappe ./bootstrap/setup-bench.sh

echo "Containers started. Open this folder in VS Code and 'Attach to running container' to finish setup."