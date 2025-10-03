#!/bin/bash
set -euo pipefail
APP_DIR="/opt/petclinic"
cd "$APP_DIR" 2>/dev/null || exit 0

# Try to stop the stack if it exists; ignore errors
/usr/bin/docker compose --env-file release.env down || true
