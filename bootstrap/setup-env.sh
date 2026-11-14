#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Internal first-install helper: creates the repository's .env from a template.
# This file is called by install.sh only. Do not use it for pipeline setup.
set -euo pipefail

if [[ "${TCF_INSTALL_INITIALIZING_ENV:-}" != "1" ]]; then
  echo "This is an internal first-install helper. Run ./install.sh to create .env." >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# Use the repository root for both the target and all project-relative paths.
source "$SCRIPT_DIR/template-lib.sh"

# Default app versions (git tag or branch). Keep these in sync with the
# DEFAULT_*_VERSION values in provision-bench.sh.
DEFAULT_FRAPPE_VERSION="v16.55.0"
DEFAULT_ERPNEXT_VERSION="v16.54.0"
DEFAULT_HRMS_VERSION="v16.53.0"
DEFAULT_RAVEN_VERSION="v3.2.0"
DEFAULT_MEET_VERSION="develop"
DEFAULT_DRIVE_VERSION="v0.4.4"
DEFAULT_INSIGHTS_VERSION="v3.15.1"
DEFAULT_WIKI_VERSION="v3.4.0"

prompt() {
  local var="$1" default="$2"
  local value
  read -r -p "$var [$default]: " value
  printf '%s' "${value:-$default}"
}

# Best-effort detection of this machine's LAN IP, for defaulting
# WEBRTC_ANNOUNCED_IP below. Tries the source address the kernel would use to
# reach the internet, then falls back to the first address hostname reports.
detect_lan_ip() {
  local ip
  ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' || true)
  if [[ -z "$ip" ]]; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  fi
  printf '%s' "$ip"
}

ENV_FILE="$ROOT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  echo ".env already exists — skipping."
  exit 0
fi

TCF_SITE_NAME=$(prompt "TCF_SITE_NAME" "tcf.local")
MEET_ANNOUNCED_IP=$(prompt "Meet SFU's public/LAN-facing address" "$(detect_lan_ip)")
MARIADB_ROOT_USERNAME=$(prompt "MARIADB_ROOT_USERNAME" "root")
MARIADB_ROOT_PASSWORD=$(prompt "MARIADB_ROOT_PASSWORD" "$(openssl rand -hex 16)")
ADMIN_PASSWORD=$(prompt "ADMIN_PASSWORD" "$(openssl rand -hex 16)")
SEAWEEDFS_ENDPOINT=$(prompt "SEAWEEDFS_ENDPOINT" "http://seaweedfs:8333")
SEAWEEDFS_ACCESS_KEY=$(prompt "SEAWEEDFS_ACCESS_KEY" "$(openssl rand -hex 16)")
SEAWEEDFS_SECRET_KEY=$(prompt "SEAWEEDFS_SECRET_KEY" "$(openssl rand -base64 32)")
JWT_SECRET=$(prompt "JWT_SECRET (Meet SFU secret, shared with the meet site's sfu_secret config)" "$(openssl rand -base64 32)")

echo "App versions (git tag or branch; press Enter to accept the default):"
FRAPPE_VERSION=$(prompt "FRAPPE_VERSION" "$DEFAULT_FRAPPE_VERSION")
ERPNEXT_VERSION=$(prompt "ERPNEXT_VERSION" "$DEFAULT_ERPNEXT_VERSION")
HRMS_VERSION=$(prompt "HRMS_VERSION" "$DEFAULT_HRMS_VERSION")
RAVEN_VERSION=$(prompt "RAVEN_VERSION" "$DEFAULT_RAVEN_VERSION")
MEET_VERSION=$(prompt "MEET_VERSION" "$DEFAULT_MEET_VERSION")
DRIVE_VERSION=$(prompt "DRIVE_VERSION" "$DEFAULT_DRIVE_VERSION")
INSIGHTS_VERSION=$(prompt "INSIGHTS_VERSION" "$DEFAULT_INSIGHTS_VERSION")
WIKI_VERSION=$(prompt "WIKI_VERSION" "$DEFAULT_WIKI_VERSION")

TCF_APPS_GIT_PREFIX=$(prompt "TCF_APPS_GIT_PREFIX" "git@github.com:FabioTessaro")
echo "Enter additional app names one at a time (blank to finish):"
TCF_APPS=""
while true; do
  read -r -p "  app: " app || break
  [[ -z "$app" ]] && break
  if [[ ! "$app" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    echo "Invalid app name '$app'. Use letters, numbers and underscores; the first character must be a letter." >&2
    continue
  fi
  TCF_APPS+=" $app"
done
TCF_APPS="$(xargs <<< "$TCF_APPS")"

render_template "$SCRIPT_DIR/templates/env.template" "$ENV_FILE" \
  "ADMIN_PASSWORD=$ADMIN_PASSWORD" \
  "TCF_SITE_NAME=$TCF_SITE_NAME" \
  "MARIADB_ROOT_USERNAME=$MARIADB_ROOT_USERNAME" \
  "MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD" \
  "SEAWEEDFS_ENDPOINT=$SEAWEEDFS_ENDPOINT" \
  "SEAWEEDFS_ACCESS_KEY=$SEAWEEDFS_ACCESS_KEY" \
  "SEAWEEDFS_SECRET_KEY=$SEAWEEDFS_SECRET_KEY" \
  "JWT_SECRET=$JWT_SECRET" \
  "MEET_ANNOUNCED_IP=$MEET_ANNOUNCED_IP" \
  "FRAPPE_VERSION=$FRAPPE_VERSION" \
  "ERPNEXT_VERSION=$ERPNEXT_VERSION" \
  "HRMS_VERSION=$HRMS_VERSION" \
  "RAVEN_VERSION=$RAVEN_VERSION" \
  "MEET_VERSION=$MEET_VERSION" \
  "DRIVE_VERSION=$DRIVE_VERSION" \
  "INSIGHTS_VERSION=$INSIGHTS_VERSION" \
  "WIKI_VERSION=$WIKI_VERSION" \
  "TCF_APPS_GIT_PREFIX=$TCF_APPS_GIT_PREFIX" \
  "TCF_APPS=$TCF_APPS"
chmod 600 "$ENV_FILE"

echo "Environment file $ENV_FILE created."
