#!/bin/bash
set -e

chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_* 2>/dev/null || true

uv tool install pre-commit

bash "$(dirname "$0")/setup-bench.sh"