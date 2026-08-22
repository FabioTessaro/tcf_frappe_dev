#!/bin/bash
set -e
# set -x

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

Frappe/ERPNext bench, site `tcf.local`. Bench root: everything below is relative to this file's directory.

## App layout

- **Vendored (dependency) apps — read for reference only, never edit:**
  `apps/frappe`, `apps/erpnext`, `apps/hrms` — upstream github.com/frappe/*. Edit/Write are blocked on these via `.claude/settings.json`; reading them to check an API/hook signature is fine, but changes belong upstream, not here.
- **Custom apps — this is the actual codebase:**
  `apps/tcf_erp`, `apps/tcf_hr`, `apps/tcf_plm`, `apps/tcf_qms`, `apps/tcf_web` — FabioTessaro's own repos. Work happens here.

## Never read or edit

`env/` (Python venv), `logs/`, `sites/**` (site data/config/backups), any `node_modules/` or `.git/` under `apps/*`. These are also denied in `.claude/settings.json`, but that only binds the Read/Edit/Write tools — when using `grep`/`find`/`rg` via Bash, explicitly exclude these paths (e.g. `--exclude-dir={env,logs,node_modules,.git} apps/frappe apps/erpnext apps/hrms/sites`) since Bash isn't path-aware at the permission level.

## Workflow — do not skip straight to code

For any feature or non-trivial change, work in this order and stop for my review between steps:

1. **Brainstorm** — discuss the feature/intent with me first; don't assume scope.
2. **Scope** — enumerate exactly which doctypes/files/hooks/behaviors need to change.
3. **Propose** — show the concrete plan/diff for review before touching files.
4. **Review** — I approve or redirect.
5. **Implement** — only after approval.

Trivial one-line fixes (typo, obvious bug with an unambiguous fix) can skip straight to implementation — everything else goes through the steps above.
EOF

bench set-config -g db_host mariadb
bench set-config -g redis_cache redis://redis-cache:6379
bench set-config -g redis_queue redis://redis-queue:6379

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

if [ ! -d "sites/tcf.local" ]; then
  bench new-site tcf.local \
    --mariadb-root-username "${MARIADB_ROOT_USERNAME:-root}" \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --no-mariadb-socket

  bench --site tcf.local set-config developer_mode 1
  bench --site tcf.local install-app erpnext
  bench --site tcf.local install-app hrms

  if [ -n "$TCF_APPS" ]; then
    for app in $TCF_APPS; do
      bench --site tcf.local install-app "$app"
    done
  fi
fi

bench --site tcf.local set-config seaweedfs_endpoint "${SEAWEEDFS_ENDPOINT}"
bench --site tcf.local set-config seaweedfs_access_key "${SEAWEEDFS_ACCESS_KEY}"
bench --site tcf.local set-config seaweedfs_secret_key "${SEAWEEDFS_SECRET_KEY}"

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
 
for bucket in ["cad-vault", "attachments-vault"]:
    try:
        s3.head_bucket(Bucket=bucket)
        print(f"Bucket '{bucket}' already exists.")
    except ClientError:
        s3.create_bucket(Bucket=bucket)
        print(f"Created bucket '{bucket}'.")
PYEOF

bench --site tcf.local clear-cache