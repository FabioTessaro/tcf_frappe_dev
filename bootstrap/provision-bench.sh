#!/bin/bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
set -e
# uv installs user tools here; bench provisioning can run in a non-login shell.
export PATH="$HOME/.local/bin:$PATH"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/template-lib.sh"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
cd "$ROOT_DIR"
# set -x

usage() {
  cat << EOF
Usage: ./bootstrap/provision-bench.sh [mode]

Flags:
  --no-default-apps   Doesn't install the default apps (erpnext, hrms, raven,
                      meet, drive, insights, wiki) in the frappe container
                      (bootstrap/provision-bench.sh). Off by default.
  -y, --yes           Don't prompt for app versions; use the values from the
                      environment (.env): FRAPPE_VERSION, ERPNEXT_VERSION,
                      HRMS_VERSION, RAVEN_VERSION, MEET_VERSION, DRIVE_VERSION,
                      INSIGHTS_VERSION. Aborts if one is
                      missing or doesn't exist.
EOF
}

WITHOUT_DEFAULT_APPS=false
USE_DEFAULTS=false
for arg in "$@"; do
  case "$arg" in
    --no-default-apps) WITHOUT_DEFAULT_APPS=true ;;
    -y|--yes) USE_DEFAULTS=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# App versions (git tag or branch) come from the environment only — normally
# the .env written by ./bootstrap/setup-env.sh:
#   FRAPPE_VERSION, ERPNEXT_VERSION, HRMS_VERSION, RAVEN_VERSION,
#   MEET_VERSION, DRIVE_VERSION, INSIGHTS_VERSION, HELPDESK_VERSION
# There are no defaults in this script. FRAPPE_VERSION is always required; the
# others are required unless --no-default-apps is used.
# ---------------------------------------------------------------------------

# Interactive = a human is attached and --yes wasn't passed.
# (devcontainer/CI runs are non-interactive and never wait for input.)
is_interactive() {
  [ "$USE_DEFAULTS" = false ] && [ -t 0 ]
}

# Exit status: 0 = ref exists, 1 = ref does not exist,
#              2 = couldn't check (network/GitHub problem).
ref_status() {
  local url="$1" ref="$2" rc=0
  git ls-remote --exit-code "$url" "refs/tags/$ref" "refs/heads/$ref" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) return 0 ;;
    2) return 1 ;;
    *) return 2 ;;
  esac
}

# resolve_version <label> <variable name> <repo url>
#
# Starts from the value already in the environment (.env).
# Interactive:     prompts (pre-filled with that value if there is one),
#                  validates, and asks again until a valid tag/branch is entered.
# Non-interactive: validates the value; aborts with a clear message if it is
#                  unset or doesn't exist, since there is no default to use.
# If GitHub can't be reached, the value is accepted unverified so a network
# blip doesn't block or loop the install.
resolve_version() {
  local label="$1" var="$2" url="$3"
  local current="${!var:-}" input status

  while true; do
    if is_interactive; then
      if [ -n "$current" ]; then
        read -r -p "${label} version [${current}]: " input
      else
        read -r -p "${label} version: " input
      fi
      current="${input:-$current}"
    fi

    if [ -z "$current" ]; then
      if is_interactive; then
        echo "${label}: a version is required." >&2
        continue
      fi
      echo "${label}: ${var} is not set — add it to .env (./bootstrap/setup-env.sh writes it) — aborting." >&2
      exit 1
    fi

    status=0
    ref_status "$url" "$current" || status=$?

    if [ "$status" -eq 0 ]; then
      break
    elif [ "$status" -eq 2 ]; then
      echo "${label}: couldn't reach ${url} to verify '${current}' — continuing unverified." >&2
      break
    fi

    echo "${label}: '${current}' is not a tag or branch of ${url}." >&2
    if is_interactive; then
      echo "Please enter a different version." >&2
      current=""
    else
      echo "${label}: fix ${var} in .env — aborting." >&2
      exit 1
    fi
  done

  printf -v "$var" '%s' "$current"
}

resolve_version "frappe" FRAPPE_VERSION https://github.com/frappe/frappe

if [ "$WITHOUT_DEFAULT_APPS" = false ]; then
  resolve_version "erpnext"  ERPNEXT_VERSION  https://github.com/frappe/erpnext
  resolve_version "hrms"     HRMS_VERSION     https://github.com/frappe/hrms
  resolve_version "raven"    RAVEN_VERSION    https://github.com/frappe/raven
  resolve_version "meet"     MEET_VERSION     https://github.com/frappe/meet
  resolve_version "drive"    DRIVE_VERSION    https://github.com/frappe/drive
  resolve_version "insights" INSIGHTS_VERSION https://github.com/frappe/insights
  resolve_version "wiki"     WIKI_VERSION     https://github.com/frappe/wiki
fi

sudo chmod 700 ~/.ssh
sudo chmod 600 ~/.ssh/id_* 2>/dev/null || true

uv tool install pre-commit

MAX_WAIT=300

echo "Waiting for MariaDB to be ready..."
WAITED=0
until mysqladmin ping -h mariadb -u ${MARIADB_ROOT_USERNAME:-root} -p"${MARIADB_ROOT_PASSWORD}" --silent 2>/dev/null; do
  WAITED=$((WAITED + 2))
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "MariaDB did not become ready within ${MAX_WAIT}s — aborting."
    exit 1
  fi
  sleep 2
done
echo "MariaDB is ready."

echo "Waiting for SeaweedFS to be ready..."
WAITED=0
until curl -sf "http://seaweedfs:8333" -o /dev/null 2>/dev/null; do
  WAITED=$((WAITED + 2))
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "SeaweedFS did not become ready within ${MAX_WAIT}s — aborting."
    exit 1
  fi
  sleep 2
done
echo "SeaweedFS is ready."

if [ ! -f frappe-bench/sites/apps.txt ]; then
  echo "No complete frappe-bench found — (re)initializing..."
  rm -rf frappe-bench
  bench init frappe-bench --frappe-branch "$FRAPPE_VERSION" --skip-redis-config-generation
fi
cd frappe-bench

# frappe-bench/ is gitignored and fully regenerated above, so seed the
# agentic-coding config here rather than relying on it surviving a rebuild.
mkdir -p .claude
render_template "$TEMPLATE_DIR/claude-settings.json.template" .claude/settings.json

render_template "$TEMPLATE_DIR/claude-bench.md.template" CLAUDE.md \
  "TCF_SITE_NAME=${TCF_SITE_NAME:-tcf.local}" \
  "MEET_SITE_NAME=${MEET_SITE_NAME:-meet.tcf.local}"

bench set-config -g db_host mariadb
bench set-config -g redis_cache redis://redis-cache:6379
bench set-config -g redis_queue redis://redis-queue:6379

if [ "$WITHOUT_DEFAULT_APPS" = false ]; then
  if [ ! -d "apps/erpnext" ]; then
    bench get-app --branch "$ERPNEXT_VERSION" erpnext
  else
    echo "apps/erpnext already exists — skipping get-app."
  fi

  if [ ! -d "apps/hrms" ]; then
    bench get-app --branch "$HRMS_VERSION" hrms
  else
    echo "apps/hrms already exists — skipping get-app."
  fi

  if [ ! -d "apps/raven" ]; then
    bench get-app --branch "$RAVEN_VERSION" https://github.com/frappe/raven
  else
    echo "apps/raven already exists — skipping get-app."
  fi

  if [ ! -d "apps/meet" ]; then
    bench get-app --branch "$MEET_VERSION" https://github.com/frappe/meet
  else
    echo "apps/meet already exists — skipping get-app."
  fi

  if [ ! -d "apps/drive" ]; then
    bench get-app --branch "$DRIVE_VERSION" https://github.com/frappe/drive
  else
    echo "apps/drive already exists — skipping get-app."
  fi

  if [ ! -d "apps/insights" ]; then
    bench get-app --branch "$INSIGHTS_VERSION" https://github.com/frappe/insights
  else
    echo "apps/insights already exists — skipping get-app."
  fi

  if [ ! -d "apps/wiki" ]; then
    bench get-app --branch "$WIKI_VERSION" https://github.com/frappe/wiki
  else
    echo "apps/wiki already exists — skipping get-app."
  fi
fi

if [ -n "$TCF_APPS" ]; then
  for app in $TCF_APPS; do
    if [ ! -d "apps/${app}" ]; then
      bench get-app "${TCF_APPS_GIT_PREFIX}/${app}.git"
    else
      echo "apps/${app} already exists — skipping get-app."
    fi
    (cd "apps/${app}" && pre-commit install 2>/dev/null || true)
  done
fi

if [ ! -d "sites/${TCF_SITE_NAME}" ]; then
  bench new-site "${TCF_SITE_NAME}" \
    --mariadb-root-username "${MARIADB_ROOT_USERNAME:-root}" \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --no-mariadb-socket

  bench --site "${TCF_SITE_NAME}" set-config developer_mode 1
  bench --site "${TCF_SITE_NAME}" set-config seaweedfs_endpoint "${SEAWEEDFS_ENDPOINT}"
  bench --site "${TCF_SITE_NAME}" set-config seaweedfs_access_key "${SEAWEEDFS_ACCESS_KEY}"
  bench --site "${TCF_SITE_NAME}" set-config seaweedfs_secret_key "${SEAWEEDFS_SECRET_KEY}"
  bench --site "${TCF_SITE_NAME}" set-config sfu_secret "${JWT_SECRET}"
  bench --site "${TCF_SITE_NAME}" set-config sfu_server_url "http://${WEBRTC_ANNOUNCED_IP}"
  bench --site "${TCF_SITE_NAME}" set-config sfu_server_port 3000 -p
  bench --site "${TCF_SITE_NAME}" set-config allow_tests true

  if [ "$WITHOUT_DEFAULT_APPS" = false ]; then
      bench --site "${TCF_SITE_NAME}" install-app erpnext
      bench --site "${TCF_SITE_NAME}" install-app hrms
      bench --site "${TCF_SITE_NAME}" install-app raven
      bench --site "${TCF_SITE_NAME}" install-app meet
      bench --site "${TCF_SITE_NAME}" install-app drive
      bench --site "${TCF_SITE_NAME}" install-app insights
      bench --site "${TCF_SITE_NAME}" install-app wiki
  fi

  if [ -n "$TCF_APPS" ]; then
    for app in $TCF_APPS; do
      bench --site "${TCF_SITE_NAME}" install-app "$app"
    done
  fi
fi


pip install boto3 --break-system-packages --quiet

python3 << 'PYEOF'
import os
import boto3
from botocore.exceptions import ClientError

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["SEAWEEDFS_ENDPOINT"],
    aws_access_key_id=os.environ["SEAWEEDFS_ACCESS_KEY"],
    aws_secret_access_key=os.environ["SEAWEEDFS_SECRET_KEY"],
)

for bucket in ["cad-vault", "attachments-vault", "drive-vault"]:
    try:
        s3.head_bucket(Bucket=bucket)
        print(f"Bucket '{bucket}' already exists.")
    except ClientError:
        s3.create_bucket(Bucket=bucket)
        print(f"Created bucket '{bucket}'.")
PYEOF

bench --site "${TCF_SITE_NAME}" clear-cache
