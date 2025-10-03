#!/bin/bash
set -euo pipefail

# Ensure target dir exists
APP_DIR="/opt/petclinic"
mkdir -p "$APP_DIR"

# Some AMIs don’t ship 'unzip' by default (helps CodeDeploy & manual debug)
command -v unzip >/dev/null 2>&1 || (yum install -y unzip || dnf install -y unzip || true)

# Normalize Windows line endings, just in case the ZIP was made on Windows
# CodeDeploy unpacks the bundle to a temp dir and then copies to $APP_DIR in Install
if [ -d /opt/codedeploy-agent/deployment-root ]; then
  DEPLOY_DIR=$(cat /opt/codedeploy-agent/deployment-root/ongoing-deployment 2>/dev/null || true)
  [ -n "$DEPLOY_DIR" ] && \
    find "$DEPLOY_DIR" -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.env" \) -exec sed -i 's/\r$//' {} +
fi
