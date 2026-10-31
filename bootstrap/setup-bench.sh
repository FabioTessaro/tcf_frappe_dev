#!/bin/bash
set -e
# set -x

usage() {
  cat << EOF
Usage: ./setup-bench.sh [mode]

Flags:
  --no-default-apps   Doesn't install the default apps (erpnext, hrms, raven,
                      meet, drive, insights) in the frappe container
                      (bootstrap/setup-bench.sh). Off by default.
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
# the .env written by bootstrap/setup-env.sh:
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
      echo "${label}: ${var} is not set — add it to .env (bootstrap/setup-env.sh writes it) — aborting." >&2
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
cat > .claude/settings.json << 'EOF'
{
  "model": "sonnet",
  "effortLevel": "medium",
  "permissions": {
    "deny": [
      "Edit(apps/frappe/**)",
      "Write(apps/frappe/**)",
      "Edit(apps/erpnext/**)",
      "Write(apps/erpnext/**)",
      "Edit(apps/hrms/**)",
      "Write(apps/hrms/**)",
      "Edit(apps/raven/**)",
      "Write(apps/raven/**)",
      "Edit(apps/meet/**)",
      "Write(apps/meet/**)",
      "Edit(apps/drive/**)",
      "Write(apps/drive/**)",
      "Edit(apps/insights/**)",
      "Write(apps/insights/**)",

      "Read(env/**)",
      "Edit(env/**)",
      "Write(env/**)",

      "Read(logs/**)",
      "Edit(logs/**)",
      "Write(logs/**)",

      "Read(sites/**)",
      "Edit(sites/**)",
      "Write(sites/**)",

      "Read(**/node_modules/**)",
      "Edit(**/node_modules/**)",
      "Write(**/node_modules/**)",

      "Read(**/.git/**)",
      "Edit(**/.git/**)",
      "Write(**/.git/**)",

      "Bash(cat env/*)",
      "Bash(cat logs/*)",
      "Bash(cat sites/*)"
    ]
  }
}
EOF

cat > CLAUDE.md << 'EOF'
# frappe-bench

Frappe/ERPNext bench, main site (`TCF_SITE_NAME` in `.env`, default `tcf.local`) plus a dedicated Meet site (`MEET_SITE_NAME` in `.env`, default `meet.tcf.local`) for frappe-meet, kept separate so it can live at its own hostname — see docker-compose.yml's `meet-sfu` service for the call-media side of it. Bench root: everything below is relative to this file's directory.

## App layout

- **Vendored (dependency) apps — read for reference only, never edit:**
  `apps/frappe`, `apps/erpnext`, `apps/hrms`, `apps/raven`, `apps/meet`, `apps/drive`, `apps/insights` — upstream github.com/frappe/*. Edit/Write are blocked on these via `.claude/settings.json`; reading them to check an API/hook signature is fine, but changes belong upstream, not here. Note: `apps/meet` tracks the now-archived frappe/meet repo rather than its frappe/suite successor — see the comment above setup-bench.sh's `bench get-app` call for that app if this ever needs revisiting.
- **Custom apps — this is the actual codebase:**
  `apps/tcf_core`, `apps/tcf_erp`, `apps/tcf_hr`, `apps/tcf_plm`, `apps/tcf_qms`, `apps/tcf_web` — FabioTessaro's own repos. Work happens here.

## Never read or edit

`env/` (Python venv), `logs/`, `sites/**` (site data/config/backups), any `node_modules/` or `.git/` under `apps/*`. These are also denied in `.claude/settings.json`, but that only binds the Read/Edit/Write tools — when using `grep`/`find`/`rg` via Bash, explicitly exclude these paths (e.g. `--exclude-dir={env,logs,node_modules,.git} apps/frappe apps/erpnext apps/hrms apps/raven apps/meet apps/drive apps/insights apps/helpdesk sites`) since Bash isn't path-aware at the permission level.

## Workflow — do not skip straight to code

Don't make use of worktrees. Edit the files directly for me to check myself and decide when to commit.
For any feature or non-trivial change, work in this order and stop for my review between steps:

1. **Brainstorm** — discuss the feature/intent with me first; don't assume scope.
2. **Scope** — enumerate exactly which doctypes/files/hooks/behaviors need to change.
3. **Propose** — show the concrete plan/diff for review before touching files.
4. **Review** — I approve or redirect.
5. **Implement** — only after approval.

Trivial one-line fixes (typo, obvious bug with an unambiguous fix) can skip straight to implementation — everything else goes through the steps above.

## Token optimization

- Don't re-read a file already open in this conversation's context.
- Prefer targeted reads of a specific path over broad directory
  exploration.
- State conclusions and file paths, not full file contents, unless asked
  to show the content itself.
- Don't restate the plan file's existing content before appending to it.
- Don't produce a summary of the whole conversation before acting.
EOF

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

  if [ "$WITHOUT_DEFAULT_APPS" = false ]; then
      bench --site "${TCF_SITE_NAME}" install-app erpnext
      bench --site "${TCF_SITE_NAME}" install-app hrms
      bench --site "${TCF_SITE_NAME}" install-app raven
      bench --site "${TCF_SITE_NAME}" install-app meet
      bench --site "${TCF_SITE_NAME}" install-app drive
      bench --site "${TCF_SITE_NAME}" install-app insights
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
