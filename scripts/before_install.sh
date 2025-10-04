#!/bin/bash
set -euo pipefail

echo "=== [BeforeInstall] $(date -Is) starting ==="

# Find this deployment’s unpacked bundle (deployment-archive)
DEPLOY_ROOT="/opt/codedeploy-agent/deployment-root"
DEPLOY_DIR="$(cat "$DEPLOY_ROOT/ongoing-deployment")"
BUNDLE_DIR="$DEPLOY_DIR/deployment-archive"

if [[ ! -f "$BUNDLE_DIR/release.env" ]]; then
  echo "ERROR: $BUNDLE_DIR/release.env not found"
  exit 1
fi

# Export variables from release.env
set -a
# strip CRs just in case (Windows line endings)
sed -i 's/\r$//' "$BUNDLE_DIR/release.env"
. "$BUNDLE_DIR/release.env"
set +a

# Validate
: "${AWS_REGION:?AWS_REGION not set (from release.env)}"
: "${IMAGE_REPO:?IMAGE_REPO not set (from release.env)}"
: "${IMAGE_TAG:?IMAGE_TAG not set (from release.env)}"

# ECR login
ECR_HOST="$(echo "$IMAGE_REPO" | awk -F/ '{print $1}')"
if ! command -v docker >/dev/null 2>&1; then
  yum install -y docker || dnf install -y docker
  systemctl enable --now docker
fi

pwdfile=$(mktemp)
aws ecr get-login-password --region "$AWS_REGION" > "$pwdfile"
cat "$pwdfile" | docker login --username AWS --password-stdin "$ECR_HOST"
rm -f "$pwdfile"

echo "=== [BeforeInstall] finished ==="
