#!/bin/bash
set -e

bash bootstrap/setup-git.sh

if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
  echo "Added $USER to docker group — log out and back in (or run 'newgrp docker') before continuing."
fi

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Edit .env with real passwords before continuing, then re-run this script."
  exit 1
fi

sudo docker compose -f .devcontainer/docker-compose.yml --env-file .env up -d
echo "Containers started. Try them out before continuing."
echo "Open this folder in VS Code and 'Reopen in Container' to finish setup. Remember to stop the containers first!"
