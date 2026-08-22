#!/bin/bash
set -e

WITH_AGENTS=false
for arg in "$@"; do
  case "$arg" in
    --with-agents=*) WITH_AGENTS="${arg#*=}" ;;
  esac
done

prompt() {
  local var="$1" default="$2" secret="$3"
  read -p "$var [$default]: " val
  echo "${val:-$default}"
}

[ -f .env ] && { echo ".env already exists — skipping."; exit 0; }

MARIADB_ROOT_USERNAME=$(prompt "MARIADB_ROOT_USERNAME" "root")
MARIADB_ROOT_PASSWORD=$(prompt "MARIADB_ROOT_PASSWORD" "$(openssl rand -hex 12)")
ADMIN_PASSWORD=$(prompt "ADMIN_PASSWORD" "$(openssl rand -hex 12)")
SEAWEEDFS_ENDPOINT=$(prompt "SEAWEEDFS_ENDPOINT" "http://seaweedfs:8333")
SEAWEEDFS_ACCESS_KEY=$(prompt "SEAWEEDFS_ACCESS_KEY" "$(openssl rand -hex 16)")
SEAWEEDFS_SECRET_KEY=$(prompt "SEAWEEDFS_SECRET_KEY" "$(openssl rand -base64 32)")

if [ "$WITH_AGENTS" = true ]; then
  ANTHROPIC_API_KEY=$(prompt "ANTHROPIC_API_KEY" "")
else
  ANTHROPIC_API_KEY=""
fi

TCF_APPS_GIT_PREFIX=$(prompt "TCF_APPS_GIT_PREFIX" "git@github.com:FabioTessaro")
echo "Enter additional app names one at a time (blank to finish):"
TCF_APPS=""
while true; do
  read -p "  app: " app
  [ -z "$app" ] && break
  TCF_APPS="$TCF_APPS $app"
done
TCF_APPS=$(echo "$TCF_APPS" | xargs)

cat > .env << ENVEOF
ADMIN_PASSWORD=$ADMIN_PASSWORD

MARIADB_ROOT_USERNAME=$MARIADB_ROOT_USERNAME
MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD
MARIADB_AUTO_UPGRADE=1

SEAWEEDFS_ENDPOINT=$SEAWEEDFS_ENDPOINT
SEAWEEDFS_ACCESS_KEY=$SEAWEEDFS_ACCESS_KEY
SEAWEEDFS_SECRET_KEY=$SEAWEEDFS_SECRET_KEY

TCF_APPS_GIT_PREFIX=$TCF_APPS_GIT_PREFIX
TCF_APPS=$TCF_APPS

ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
ENVEOF

echo "Environment file .env created."