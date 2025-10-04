#!/bin/bash
set -euo pipefail
APP_DIR="/opt/petclinic"
cd "$APP_DIR"

# Read port from the env file (SERVER_PORT default 8086)
source "$APP_DIR/release.env"
PORT="${SERVER_PORT:-8086}"

# Poll health for up to ~30s
for i in {1..30}; do
  if curl -fsS "http://127.0.0.1:${PORT}/actuator/health" >/dev/null 2>&1 || \
     curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
    echo "Service is healthy on port ${PORT}"
    exit 0
  fi
  sleep 1
done

echo "Service did not become healthy on port ${PORT}"
exit 1
