#!/bin/bash
set -e

cd "$(dirname "$0")/.."
source .env

: "${MARIADB_ROOT_USERNAME:?MARIADB_ROOT_USERNAME is not set}"
: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD is not set}"

mkdir -p .devcontainer

cat > .devcontainer/devcontainer.json <<EOF
{
  "name": "TCF-DEVELOPMENT",
  "remoteUser": "frappe",
  "workspaceFolder": "/workspace",
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python",
        "ms-vscode.live-server",
        "grapecity.gc-excelviewer",
        "mtxr.sqltools",
        "mtxr.sqltools-driver-mysql",
        "vue.volar",
        "esbenp.prettier-vscode",
        "charliermarsh.ruff"
      ],
      "settings": {
        "terminal.integrated.profiles.linux": {
          "frappe bash": {
            "path": "/bin/bash"
          }
        },
        "terminal.integrated.defaultProfile.linux": "frappe bash",
        "debug.node.autoAttach": "disabled",
        "sqltools.connections": [
          {
            "mysqlOptions": {
              "authProtocol": "default",
              "enableSsl": "Disabled"
            },
            "ssh": "Disabled",
            "previewLimit": 50,
            "server": "mariadb",
            "port": 3306,
            "driver": "MariaDB",
            "name": "MariaDB",
            "username": "${MARIADB_ROOT_USERNAME}",
            "password": "${MARIADB_ROOT_PASSWORD}",
            "database": "mysql"
          }
        ]
      }
    }
  }
}
EOF