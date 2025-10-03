#!/bin/bash
# no -e (it causes exit on harmless tests); keep tracing & -u/-o pipefail
set -xuo pipefail

APP_DIR="/opt/petclinic"
mkdir -p "$APP_DIR" || true

# Ensure unzip exists (best-effort; never fail the hook)
if ! command -v unzip >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf -y install unzip || true
  elif command -v yum >/dev/null 2>&1; then
    sudo yum -y install unzip || true
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y || true
    sudo apt-get install -y unzip || true
  fi
fi

# Normalize CRLF -> LF inside this deployment's archive (best-effort)
DEPLOY_FILE="/opt/codedeploy-agent/deployment-root/ongoing-deployment"
if [[ -f "$DEPLOY_FILE" ]]; then
  DEPLOY_DIR_NOW="$(cat "$DEPLOY_FILE" 2>/dev/null | tr -d '\n')"
  if [[ -n "${DEPLOY_DIR_NOW:-}" && -d "$DEPLOY_DIR_NOW/deployment-archive" ]]; then
    find "$DEPLOY_DIR_NOW/deployment-archive" \
      -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.env" \) \
      -exec sed -i 's/\r$//' {} + || true
  fi
fi

exit 0
