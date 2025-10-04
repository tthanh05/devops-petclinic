#!/bin/bash
set -euo pipefail

echo "=== [BeforeInstall] $(date -Is) starting ==="

DEPLOY_ROOT="/opt/codedeploy-agent/deployment-root"
OD="$DEPLOY_ROOT/ongoing-deployment"

# Resolve the current deployment directory regardless of agent flavor
if [[ -L "$OD" ]]; then
  DEPLOY_DIR="$(readlink -f "$OD")"
elif [[ -f "$OD" ]]; then
  DEPLOY_DIR="$(cat "$OD")"
elif [[ -d "$OD" ]]; then
  DEPLOY_DIR="$OD"
else
  # Fallback: newest d-* folder
  DEPLOY_DIR="$(ls -td "$DEPLOY_ROOT"/d-* 2>/dev/null | head -1 || true)"
fi

if [[ -z "${DEPLOY_DIR:-}" || ! -d "$DEPLOY_DIR" ]]; then
  echo "ERROR: Cannot resolve CodeDeploy deployment directory from $OD"
  exit 1
fi

BUNDLE_DIR="$DEPLOY_DIR/deployment-archive"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "ERROR: deployment-archive not found under $DEPLOY_DIR"
  exit 1
fi

# Load release variables produced by Jenkins (make sure LF line endings)
if [[ ! -f "$BUNDLE_DIR/release.env" ]]; then
  echo "ERROR: $BUNDLE_DIR/release.env not found"
  exit 1
fi

sed -i 's/\r$//' "$BUNDLE_DIR/release.env"
set -a
. "$BUNDLE_DIR/release.env"
set +a

: "${AWS_REGION:?AWS_REGION not set in release.env}"
: "${IMAGE_REPO:?IMAGE_REPO not set in release.env}"
: "${IMAGE_TAG:?IMAGE_TAG not set in release.env}"

# Ensure Docker present and started
if ! command -v docker >/dev/null 2>&1; then
  (yum install -y docker || dnf install -y docker)
  systemctl enable --now docker
fi

# ECR login (no pipes in sh)
ECR_HOST="$(echo "$IMAGE_REPO" | awk -F/ '{print $1}')"
pwdfile=$(mktemp)
aws ecr get-login-password --region "$AWS_REGION" > "$pwdfile"
cat "$pwdfile" | docker login --username AWS --password-stdin "$ECR_HOST"
rm -f "$pwdfile"

echo "=== [BeforeInstall] finished OK ==="
