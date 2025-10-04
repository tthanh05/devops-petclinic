#!/bin/bash
set -euo pipefail

echo "=== [ApplicationStart] $(date -Is) ==="

APP_DIR="/opt/petclinic"
cd "$APP_DIR"

# Boot the stack
/usr/bin/docker compose --env-file release.env -f docker-compose.prod.yml up -d

# Optional: wait a few seconds before health checks
sleep 5

echo "=== [ApplicationStart] done ==="
