#!/bin/bash
set -euo pipefail

echo "=== [BeforeInstall] $(date -Is) starting ==="

DEPLOY_ROOT="/opt/codedeploy-agent/deployment-root"
OD="$DEPLOY_ROOT/ongoing-deployment"

resolve_deploy_dir() {
  local cand=""

  if [[ -L "$OD" ]]; then
    cand="$(readlink -f "$OD")"
  elif [[ -f "$OD" ]]; then
    cand="$(cat "$OD")"
  elif [[ -d "$OD" ]]; then
    cand="$OD"
  fi

  # If we have a candidate, and it contains deployment-archive, use it
  if [[ -n "${cand:-}" && -d "$cand/deployment-archive" ]]; then
    echo "$cand"
    return
  fi

  # If ongoing-deployment is a directory, try newest d-* inside it
  if [[ -d "$OD" ]]; then
    local inner="$(ls -td "$OD"/d-* 2>/dev/null | head -1 || true)"
    if [[ -n "$inner" && -d "$inner/deployment-archive" ]]; then
      echo "$inner"
      return
    fi
  fi

  # Fallback: newest d-* under the root
  local root_latest="$(ls -td "$DEPLOY_ROOT"/d-* 2>/dev/null | head -1 || true)"
  if [[ -n "$root_latest" && -d "$root_latest/deployment-archive" ]]; then
    echo "$root_latest"
    return
  fi

  echo ""
}

DEPLOY_DIR="$(resolve_deploy_dir)"

if [[ -z "$DEPLOY_DIR" ]]; then
  echo "ERROR: cannot resolve deployment directory from $OD"
  echo "DEBUG: tree of $DEPLOY_ROOT:"
  ls -lah "$DEPLOY_ROOT" || true
  exit 1
fi

BUNDLE_DIR="$DEPLOY_DIR/deployment-archive"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "ERROR: deployment-archive not found under $DEPLOY_DIR"
  echo "DEBUG: ls of $DEPLOY_DIR:"
  ls -lah "$DEPLOY_DIR" || true
  exit 1
fi

# Load Jenkins vars
if [[ ! -f "$BUNDLE_DIR/release.env" ]]; then
  echo "ERROR: $BUNDLE_DIR/release.env not found"
  exit 1
fi
sed -i 's/\r$//' "$BUNDLE_DIR/release.env"
set -a; . "$BUNDLE_DIR/release.env"; set +a

: "${AWS_REGION:?missing in release.env}"
: "${IMAGE_REPO:?missing in release.env}"
: "${IMAGE_TAG:?missing in release.env}"

# Ensure docker + login to ECR
if ! command -v docker >/dev/null 2>&1; then
  (yum install -y docker || dnf install -y docker)
  systemctl enable --now docker
fi

ECR_HOST="$(echo "$IMAGE_REPO" | awk -F/ '{print $1}')"
tmp=$(mktemp)
aws ecr get-login-password --region "$AWS_REGION" > "$tmp"
cat "$tmp" | docker login --username AWS --password-stdin "$ECR_HOST"
rm -f "$tmp"

echo "=== [BeforeInstall] resolved DEPLOY_DIR=$DEPLOY_DIR OK ==="
