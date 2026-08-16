#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Stopping containers..."
docker compose -f .devcontainer/docker-compose.yml --env-file .env down

echo "Removing dangling images, stopped containers, unused networks, build cache..."
docker system prune -f

if [ "$1" == "--deep" ]; then
  echo "Deep clean: removing ALL unused images too (will re-pull on next start)..."
  docker image prune -a -f
fi

echo "Done. Named volumes (mariadb-data and seaweedfs-data) were preserved:"
docker volume ls
