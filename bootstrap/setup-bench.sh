#!/bin/bash
set -e
# set -x

usage() {
  cat << EOF
Usage: ./setup-bench.sh [mode]

Flags:
  --no-default-apps   Doesn't install the default erpnext and hrms apps in the
                      frappe container (bootstrap/setup-bench.sh). Off by
                      default.
EOF
}

WITHOUT_DEFAULT_APPS=false
for arg in "$@"; do
  case "$arg" in
    --no-default-apps) WITHOUT_DEFAULT_APPS=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

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
  bench init frappe-bench --frappe-branch version-16 --skip-redis-config-generation
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
  `apps/frappe`, `apps/erpnext`, `apps/hrms`, `apps/raven`, `apps/meet` — upstream github.com/frappe/*. Edit/Write are blocked on these via `.claude/settings.json`; reading them to check an API/hook signature is fine, but changes belong upstream, not here. Note: `apps/meet` tracks the now-archived frappe/meet repo rather than its frappe/suite successor — see the comment above setup-bench.sh's `bench get-app` call for that app if this ever needs revisiting.
- **Custom apps — this is the actual codebase:**
  `apps/tcf_erp`, `apps/tcf_hr`, `apps/tcf_plm`, `apps/tcf_qms`, `apps/tcf_web` — FabioTessaro's own repos. Work happens here.
 
## Never read or edit
 
`env/` (Python venv), `logs/`, `sites/**` (site data/config/backups), any `node_modules/` or `.git/` under `apps/*`. These are also denied in `.claude/settings.json`, but that only binds the Read/Edit/Write tools — when using `grep`/`find`/`rg` via Bash, explicitly exclude these paths (e.g. `--exclude-dir={env,logs,node_modules,.git} apps/frappe apps/erpnext apps/hrms apps/raven apps/meet sites`) since Bash isn't path-aware at the permission level.
 
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
    bench get-app --branch version-16 erpnext
  else
    echo "apps/erpnext already exists — skipping get-app."
  fi

  if [ ! -d "apps/hrms" ]; then
    bench get-app --branch version-16 hrms
  else
    echo "apps/hrms already exists — skipping get-app."
  fi

  if [ ! -d "apps/raven" ]; then
    bench get-app --branch main https://github.com/frappe/raven
  else
    echo "apps/raven already exists — skipping get-app."
  fi

  # frappe/meet was archived in favour of frappe/suite, but its repo still
  # clones fine and its last-published sfu-server image is still pullable
  # (see docker-compose.yml's meet-sfu service), so it stays a standalone
  # app here rather than pulling in all of Suite (drive/writer/sheets/
  # slides/mail/calendar) for just video calls. If Suite's actively
  # maintained meet ever becomes the better trade-off, swap this line and
  # the meet-sfu image for frappe/suite's equivalents.
  if [ ! -d "apps/meet" ]; then
    bench get-app --branch develop https://github.com/frappe/meet
  else
    echo "apps/meet already exists — skipping get-app."
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
  
  if [ "$WITHOUT_DEFAULT_APPS" = false ]; then
      bench --site "${TCF_SITE_NAME}" install-app erpnext
      bench --site "${TCF_SITE_NAME}" install-app hrms
      bench --site "${TCF_SITE_NAME}" install-app raven
  fi
 
  if [ -n "$TCF_APPS" ]; then
    for app in $TCF_APPS; do
      bench --site "${TCF_SITE_NAME}" install-app "$app"
    done
  fi
fi

# frappe-meet lives on its own site rather than ${TCF_SITE_NAME}, so it can
# be reached at its own hostname (MEET_SITE_NAME) both here on the local
# network and, later, in production (e.g. meet.tcf-group.com alongside
# www.tcf-group.com) — matching how frappe/meet's own docs always give it
# a dedicated site (meet.localhost) rather than bundling it in.
if [ "$WITHOUT_DEFAULT_APPS" = false ] && [ ! -d "sites/${MEET_SITE_NAME}" ]; then
  bench new-site "${MEET_SITE_NAME}" \
    --mariadb-root-username "${MARIADB_ROOT_USERNAME:-root}" \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --no-mariadb-socket
 
  bench --site "${MEET_SITE_NAME}" install-app meet
 
  # Must match the sfu-server container's JWT_SECRET (docker-compose.yml)
  # exactly — this is how a meeting link mints a token the SFU will trust.
  bench --site "${MEET_SITE_NAME}" set-config sfu_secret "${JWT_SECRET}"
fi


bench --site "${TCF_SITE_NAME}" set-config seaweedfs_endpoint "${SEAWEEDFS_ENDPOINT}"
bench --site "${TCF_SITE_NAME}" set-config seaweedfs_access_key "${SEAWEEDFS_ACCESS_KEY}"
bench --site "${TCF_SITE_NAME}" set-config seaweedfs_secret_key "${SEAWEEDFS_SECRET_KEY}"

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
 
for bucket in ["cad-vault", "attachments-vault", "raven-vault"]:
    try:
        s3.head_bucket(Bucket=bucket)
        print(f"Bucket '{bucket}' already exists.")
    except ClientError:
        s3.create_bucket(Bucket=bucket)
        print(f"Created bucket '{bucket}'.")
PYEOF

bench --site tcf.local clear-cache