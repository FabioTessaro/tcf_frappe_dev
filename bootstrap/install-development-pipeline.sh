#!/usr/bin/env bash
# One entry point for installing the tools required by the Vue/Frappe pipeline.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=bootstrap/pipeline-common.sh
source "$SCRIPT_DIR/pipeline-common.sh"

SKIP_SYSTEM_TOOLS=false
DEFER_APP_SELECTION=false
SKIP_DEVTOOLS=false
for arg in "$@"; do
  case "$arg" in
    --skip-system-tools) SKIP_SYSTEM_TOOLS=true ;;
    --defer-app-selection) DEFER_APP_SELECTION=true ;;
    --skip-devtools) SKIP_DEVTOOLS=true ;;
    -h|--help)
      cat <<HELP
Usage: bootstrap/install-development-pipeline.sh [options]

  --skip-system-tools     Do not install apt packages, uv or pre-commit
  --defer-app-selection   Install common tools even when core selection needs a TTY
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

NODE_VERSION="${NODE_VERSION:-26}"
export NODE_VERSION
bash "$SCRIPT_DIR/install-node-toolchain.sh"

# install-node-toolchain.sh runs in a child process; load its nvm-managed Node into this
# process so the following frontend installer scripts can use node/pnpm.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"
nvm use "$NODE_VERSION" --silent >/dev/null

CORE_SELECTION_STATUS=0
if pipeline_select_core_app "$SITE_NAME"; then
  FRONTEND_DIR="$PIPELINE_BENCH_DIR/apps/$CORE_APP/frontend"
  export FRONTEND_DIR
  bash "$SCRIPT_DIR/install-frontend-dependencies.sh" "$FRONTEND_DIR"
  bash "$SCRIPT_DIR/install-playwright-browsers.sh" "$FRONTEND_DIR"
else
  CORE_SELECTION_STATUS=$?
  if [[ "$CORE_SELECTION_STATUS" -eq 2 && "$DEFER_APP_SELECTION" == true ]]; then
    echo "Deferring frontend dependency installation until a core app is selected interactively."
  else
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
  Core app: ${CORE_APP:-not selected yet}
SUMMARY
if [[ -z "${CORE_APP:-}" ]]; then
  echo "Run ./setup-env.sh from an interactive terminal to select the core app and install its frontend dependencies."
fi
