#!/usr/bin/env bash
# Checks the devcontainer for the tools the portal workflow needs.
# Edit BENCH_DIR and SITE for your setup.

BENCH_DIR="${BENCH_DIR:-/workspace/frappe-bench}"
SITE="${SITE:-tcf.local}"
FRONTEND_DIR="${FRONTEND_DIR:-$BENCH_DIR/apps/core/frontend}"

missing_required=0

check() {
  # check <label> <required|optional> <command...>
  local label="$1" level="$2"; shift 2
  if out="$("$@" 2>&1 | head -n 1)"; then
    printf "OK       %-22s %s\n" "$label" "$out"
  else
    printf "MISSING  %-22s (%s)\n" "$label" "$level"
    [ "$level" = "required" ] && missing_required=1
  fi
}

echo "== Base =="
check git       required git --version
check curl      required curl --version
check jq        required jq --version

echo "== Backend =="
check python    required "$BENCH_DIR/env/bin/python" --version
check bench     required bench --version
check ruff      optional "$BENCH_DIR/env/bin/ruff" --version
check pre-commit optional "$BENCH_DIR/env/bin/pre-commit" --version
check mariadb   required mysqladmin -h "${DB_HOST:-mariadb}" -uroot -p"${DB_ROOT_PASSWORD:-123}" ping
check redis     required redis-cli -h "${REDIS_HOST:-redis-cache}" ping

echo "== Frontend =="
check node      required node --version
check corepack  required corepack --version
check pnpm      required pnpm --version

if [ -d "$FRONTEND_DIR" ]; then
  cd "$FRONTEND_DIR" || exit 1
  check node_modules required test -d node_modules
  for bin in vite vitest vue-tsc eslint stylelint prettier playwright tailwindcss; do
    check "$bin" required pnpm exec "$bin" --version
  done
  check "playwright-browsers" required bash -c 'ls ~/.cache/ms-playwright 2>/dev/null | grep -q chromium'
else
  echo "SKIP     frontend folder not found: $FRONTEND_DIR"
fi

echo "== Ports (listening) =="
for p in 8000 9000 5173; do
  if (ss -ltn 2>/dev/null | grep -q ":$p "); then echo "LISTEN   $p"; else echo "idle     $p"; fi
done

exit $missing_required