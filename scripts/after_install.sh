#!/bin/bash
set -euo pipefail
APP_DIR="/opt/petclinic"
cd "$APP_DIR"

# Show docker/compose versions for debugging
docker --version || true
/usr/bin/docker compose version || true

# If your compose file references remote images, pulling now can surface auth/network issues early
/usr/bin/docker compose --env-file release.env -f docker-compose.prod.yml pull || true
