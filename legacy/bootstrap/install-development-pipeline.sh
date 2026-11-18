#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# One entry point for installing the tools required by the Vue/Frappe pipeline.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=bootstrap/pipeline-common.sh
source "$SCRIPT_DIR/pipeline-common.sh"

SKIP_SYSTEM_TOOLS=false
SKIP_DEVTOOLS=false
for arg in "$@"; do
  case "$arg" in
    --skip-system-tools) SKIP_SYSTEM_TOOLS=true ;;
    --skip-devtools) SKIP_DEVTOOLS=true ;;
    -h|--help)
      cat <<HELP
Usage: bootstrap/install-development-pipeline.sh [options]

  --skip-system-tools     Do not install apt packages, uv or pre-commit
  --skip-devtools         Do not generate the VS Code workspace or Git hooks
HELP
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$ROOT_DIR"
export PATH="$HOME/.local/bin:$PATH"
SITE_NAME=$(pipeline_site_name)
export SITE="$SITE_NAME"

if [[ "$SKIP_SYSTEM_TOOLS" == false ]]; then
  bash "$SCRIPT_DIR/install-system-dependencies.sh"
fi

NODE_VERSION="${NODE_VERSION:-24}"
export NODE_VERSION
bash "$SCRIPT_DIR/install-node-toolchain.sh"

# install-node-toolchain.sh runs in a child process; load its nvm-managed Node into this
# process so the following frontend installer scripts can use node/pnpm.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"
nvm use "$NODE_VERSION" --silent >/dev/null

# A bench may be provisioned without any custom apps (install.sh
# --no-custom-apps, or CORE_APP=none at the .env prompt). Then there is no
# core frontend to install: build the bench assets and skip the rest.
CONFIGURED_CORE_APP="$(pipeline_config_value CORE_APP)"
CONFIGURED_APPS="$(pipeline_config_value TCF_APPS)"
CORE_APP_STATUS=""

if [[ -z "${CONFIGURED_CORE_APP// /}" && -z "${CONFIGURED_APPS// /}" ]]; then
  echo "No custom apps configured (CORE_APP and TCF_APPS are empty) — skipping the core frontend setup."
  CORE_APP_STATUS="none (no custom apps configured)"

  log_step "Building Frappe application assets"
  (
    cd "$PIPELINE_BENCH_DIR"
    bench build
  )
else
  CORE_SELECTION_STATUS=0
  if pipeline_select_core_app "$SITE_NAME"; then
    FRONTEND_DIR="$PIPELINE_BENCH_DIR/apps/$CORE_APP/frontend"
    export FRONTEND_DIR

    bash "$SCRIPT_DIR/install-frontend-dependencies.sh" "$FRONTEND_DIR"

    log_step "Building Frappe application assets"
    (
      cd "$PIPELINE_BENCH_DIR"
      bench build
    )

    bash "$SCRIPT_DIR/install-playwright-browsers.sh" "$FRONTEND_DIR"
  else
    CORE_SELECTION_STATUS=$?
    echo "Core app selection failed. Check CORE_APP and TCF_APPS in .env." >&2
    exit "$CORE_SELECTION_STATUS"
  fi
fi

if [[ "$SKIP_DEVTOOLS" == false ]]; then
  bash "$SCRIPT_DIR/configure-devtools.sh"
fi

cat <<SUMMARY

Pipeline bootstrap complete.
  Node.js / Corepack / pnpm: installed
  System tools / uv / pre-commit: $([[ "$SKIP_SYSTEM_TOOLS" == true ]] && echo 'not changed (--skip-system-tools)' || echo 'checked and installed')
  Core app: ${CORE_APP_STATUS:-${CORE_APP:-not selected yet}}
SUMMARY
