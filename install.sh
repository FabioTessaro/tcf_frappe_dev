#!/bin/bash
set -e

if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Edit .env with real passwords before continuing, then re-run this script."
  exit 1
fi

docker compose -f .devcontainer/docker-compose.yml --env-file .env up -d
echo "Containers up. Open this folder in VS Code and 'Reopen in Container' to finish setup."