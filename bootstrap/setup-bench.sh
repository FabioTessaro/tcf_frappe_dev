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