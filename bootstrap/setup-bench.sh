#!/bin/bash
set -e

echo "Waiting for MariaDB to be ready..."
MAX_WAIT=300
WAITED=0
until mysqladmin ping -h mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" --silent 2>/dev/null; do
  WAITED=$((WAITED + 2))
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "MariaDB did not become ready within ${MAX_WAIT}s — aborting."
    exit 1
  fi
  sleep 2
done
echo "MariaDB is ready."

cd frappe-bench 2>/dev/null || {
  bench init frappe-bench --frappe-branch version-16 --skip-redis-config-generation
  cd frappe-bench
}

bench set-config -g db_host mariadb
bench set-config -g redis_cache redis://redis-cache:6379
bench set-config -g redis_queue redis://redis-queue:6379

bench get-app --branch version-16 erpnext
bench get-app --branch version-16 hrms

if [ -n "$TCF_APPS" ]; then
  for app in $TCF_APPS; do
    bench get-app "${TCF_APPS_GIT_PREFIX}/${app}.git"
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

bench --site tcf.local clear-cache
