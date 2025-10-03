#!/usr/bin/env bash
# scripts/before_install.sh
set -Eeuo pipefail
IFS=$'\n\t'

# log everything to /var/log/codedeploy-hooks.log and to the CodeDeploy console
exec > >(tee -a /var/log/codedeploy-hooks.log) 2>&1
echo "=== [BeforeInstall] $(date -Is) starting ==="

APP_DIR="/opt/petclinic"
mkdir -p "$APP_DIR"

# Ensure unzip exists (quietly); some AL2 images don’t have it
if ! command -v unzip >/dev/null 2>&1; then
  echo "[BeforeInstall] installing unzip..."
  (yum -y install unzip || dnf -y install unzip || true)
fi

# Normalize CRLF just in case the archive was zipped on Windows
if [ -d /opt/codedeploy-agent/deployment-root ]; then
  DEPLOY_DIR_FILE="/opt/codedeploy-agent/deployment-root/ongoing-deployment"
  if [ -r "$DEPLOY_DIR_FILE" ]; then
    DEPLOY_DIR="$(cat "$DEPLOY_DIR_FILE")"
    if [ -n "${DEPLOY_DIR:-}" ] && [ -d "$DEPLOY_DIR" ]; then
      echo "[BeforeInstall] normalizing line endings in $DEPLOY_DIR"
      find "$DEPLOY_DIR" -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.env" \) \
        -exec sed -i 's/\r$//' {} +
    fi
  fi
fi

echo "=== [BeforeInstall] $(date -Is) finished OK ==="
