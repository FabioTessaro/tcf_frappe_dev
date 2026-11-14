#!/usr/bin/env bash

# Consistent progress, warning and failure output.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/logging.sh"
log_init "${BASH_SOURCE[0]}"
# Provision missing dependencies and install the single core-owned frontend.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/frontend.package.json.template"
CORE_TEMPLATE="$SCRIPT_DIR/templates/core-app.package.json.template"
FRONTEND_DIR="${1:-${FRONTEND_DIR:-}}"

if [[ -z "$FRONTEND_DIR" ]]; then
  echo "Usage: $0 <core-frontend-directory>" >&2
  exit 2
fi

mkdir -p "$FRONTEND_DIR"
APP_DIR="$(dirname "$FRONTEND_DIR")"

command -v node >/dev/null 2>&1 || { echo "Node.js is not installed; run bootstrap/install-node-toolchain.sh first." >&2; exit 1; }

# Add missing scripts and dependencies without overwriting project-specific
# choices already present in either package.json.
node --input-type=module - "$FRONTEND_DIR/package.json" "$TEMPLATE" "$APP_DIR/package.json" "$CORE_TEMPLATE" "$(basename "$APP_DIR")" <<'NODE'
import fs from 'node:fs';

const [frontendFile, frontendTemplateFile, appFile, appTemplateFile, appName] = process.argv.slice(2);
const readJson = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
const writeJson = (file, value) => fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
const mergeMissing = (target, defaults) => {
  for (const [key, value] of Object.entries(defaults ?? {})) {
    if (target[key] === undefined) target[key] = value;
  }
};

const frontend = fs.existsSync(frontendFile) ? readJson(frontendFile) : {};
const frontendDefaults = readJson(frontendTemplateFile);
frontend.name ??= frontendDefaults.name;
frontend.private ??= true;
frontend.type ??= frontendDefaults.type;
frontend.engines ??= {};
mergeMissing(frontend.engines, frontendDefaults.engines);
frontend.scripts ??= {};
mergeMissing(frontend.scripts, frontendDefaults.scripts);
frontend.dependencies ??= {};
mergeMissing(frontend.dependencies, frontendDefaults.dependencies);
frontend.devDependencies ??= {};
mergeMissing(frontend.devDependencies, frontendDefaults.devDependencies);
writeJson(frontendFile, frontend);

const app = fs.existsSync(appFile) ? readJson(appFile) : {};
const appDefaults = readJson(appTemplateFile);
app.name ??= appName.replaceAll('_', '-');
app.private ??= true;
app.scripts ??= {};
mergeMissing(app.scripts, appDefaults.scripts);
writeJson(appFile, app);
NODE

if [[ ! -f "$FRONTEND_DIR/package.json" || ! -f "$APP_DIR/package.json" ]]; then
  echo "Could not create the frontend or app-level package manifest." >&2
  exit 1
fi

PNPM_WORKSPACE_CONFIG="$FRONTEND_DIR/pnpm-workspace.yaml"

if [[ ! -f "$PNPM_WORKSPACE_CONFIG" ]]; then
  cp "$SCRIPT_DIR/templates/pnpm-workspace.yaml.template" \
    "$PNPM_WORKSPACE_CONFIG"
  echo "Created pnpm-workspace.yaml with approved dependency build scripts."
fi

command -v node >/dev/null 2>&1 || { echo "Node.js is not installed; run bootstrap/install-node-toolchain.sh first." >&2; exit 1; }
command -v corepack >/dev/null 2>&1 || { echo "Corepack is not installed; run bootstrap/install-node-toolchain.sh first." >&2; exit 1; }

# Pin the package manager in the project manifest. If the project already pins
# pnpm, preserve its chosen version; otherwise pin the active exact version.
ACTIVE_PNPM_VERSION=$(pnpm --version)
node --input-type=module - "$FRONTEND_DIR/package.json" "$APP_DIR/package.json" "$ACTIVE_PNPM_VERSION" <<'NODE'
import fs from 'node:fs';
const files = process.argv.slice(2, 4);
const activeVersion = process.argv[4];
for (const file of files) {
  const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (pkg.packageManager && !pkg.packageManager.startsWith('pnpm@')) {
    throw new Error(`${file}: expected packageManager to use pnpm, found: ${pkg.packageManager}`);
  }
  if (!pkg.packageManager) pkg.packageManager = `pnpm@${activeVersion}`;
  fs.writeFileSync(file, `${JSON.stringify(pkg, null, 2)}\n`);
}
NODE

PACKAGE_MANAGER=$(node -p 'require(process.argv[1]).packageManager' "$FRONTEND_DIR/package.json")
corepack prepare "$PACKAGE_MANAGER" --activate

cd "$FRONTEND_DIR"
echo "Installing frontend dependencies (updating pnpm-lock.yaml only when manifests require it)..."
pnpm install --no-frozen-lockfile

echo "Frontend dependencies installed in $FRONTEND_DIR."
