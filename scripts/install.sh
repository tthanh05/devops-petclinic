#!/bin/bash
set -euo pipefail
# Copy the deployment archive contents into /opt/petclinic
APP_DIR="/opt/petclinic"

# Find where the agent unpacked this revision
DEPLOY_DIR=$(cat /opt/codedeploy-agent/deployment-root/ongoing-deployment 2>/dev/null | tr -d '\n')

# The files are under deployment-archive/
if [ -z "$DEPLOY_DIR" ] || [ ! -d "$DEPLOY_DIR/deployment-archive" ]; then
  echo "Could not locate deployment-archive. DEPLOY_DIR=$DEPLOY_DIR"
  exit 1
fi

mkdir -p "$APP_DIR"
cp -f "$DEPLOY_DIR/deployment-archive/release.env" "$APP_DIR/"
cp -f "$DEPLOY_DIR/deployment-archive/docker-compose.prod.yml" "$APP_DIR/"
# copy scripts too (optional, for local troubleshooting)
/bin/cp -rf "$DEPLOY_DIR/deployment-archive/scripts" "$APP_DIR/scripts"

# Make sure scripts are executable & endings are LF
find "$APP_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \; -exec sed -i 's/\r$//' {} \;
sed -i 's/\r$//' "$APP_DIR/docker-compose.prod.yml" "$APP_DIR/release.env" || true
