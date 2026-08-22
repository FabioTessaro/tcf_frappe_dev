#!/bin/bash
set -e

cd "$(dirname "$0")/.."

mkdir -p .devcontainer

cat > .devcontainer/devcontainer.json <<EOF
{
  "name": "TCF-DEVELOPMENT",
  "dockerComposeFile": "docker-compose.yml",
  "service": "frappe",
  "remoteUser": "frappe",
  "workspaceFolder": "/workspace",
  "shutdownAction": "none",

  // Runs on the VM, before the container exists. Good for anything the
  // compose file itself depends on (e.g. generating a .env).
  // "initializeCommand": "bash ${localWorkspaceFolder}/bootstrap/<INITIALIZE_SCRIPT_PLACEHOLDER>.sh",

  // Runs inside the container, once, the first time it's created.
  "postCreateCommand": "bash ${containerWorkspaceFolder}/bootstrap/setup-bench.sh",

  // Runs inside the container every time it starts (not just on creation).
  // "postStartCommand": "bash ${containerWorkspaceFolder}/bootstrap/<POST_START_SCRIPT_PLACEHOLDER>.sh",

  // Runs inside the container every time VS Code attaches.
  // "postAttachCommand": "bash ${containerWorkspaceFolder}/bootstrap/<POST_ATTACH_SCRIPT_PLACEHOLDER>.sh",

  "customizations": {
    "vscode": {
      "extensions": []
    }
  }
}
EOF
