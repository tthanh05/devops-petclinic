# #!/usr/bin/env bash
# set -Eeuo pipefail
# IFS=$'\n\t'

# # log to a file and console
# exec > >(tee -a /var/log/codedeploy-hooks.log) 2>&1
# echo "=== [BeforeInstall] $(date -Is) starting ==="

# APP_DIR="/opt/petclinic"
# mkdir -p "$APP_DIR" || true

# # best-effort unzip
# if ! command -v unzip >/dev/null 2>&1; then
#   (yum -y install unzip || dnf -y install unzip || true)
# fi

# DEPLOY_ROOT="/opt/codedeploy-agent/deployment-root"
# DEPLOY_DIR=""

# if [[ -d "$DEPLOY_ROOT" ]]; then
#   # Case 1: old layout — ongoing-deployment is a file containing the d-* path
#   if [[ -f "$DEPLOY_ROOT/ongoing-deployment" ]]; then
#     DEPLOY_DIR="$(tr -d '\n' < "$DEPLOY_ROOT/ongoing-deployment" || true)"
#   fi

#   # Case 2: new layout — ongoing-deployment is a dir, or the file was empty
#   if [[ -z "${DEPLOY_DIR:-}" ]]; then
#     DEPLOY_DIR="$(ls -1dt "$DEPLOY_ROOT"/d-* 2>/dev/null | head -1 || true)"
#   fi
# fi

# echo "[BeforeInstall] DEPLOY_DIR='${DEPLOY_DIR:-<none>}'"

# # Normalize CRLF inside the unpacked bundle (best effort)
# if [[ -n "${DEPLOY_DIR:-}" && -d "$DEPLOY_DIR/deployment-archive" ]]; then
#   find "$DEPLOY_DIR/deployment-archive" \
#     -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.env" \) \
#     -exec sed -i 's/\r$//' {} + || true
#!/bin/bash
set -euo pipefail

echo "=== [BeforeInstall] $(date -Is) starting ==="

APP_DIR="/opt/petclinic"
mkdir -p "$APP_DIR"

# The release.env is copied by CodeDeploy; it sets AWS_REGION (and other vars)
if [ -f "$APP_DIR/release.env" ]; then
  # shellcheck disable=SC1091
  source "$APP_DIR/release.env"
fi

: "${AWS_REGION:?AWS_REGION is not set (from release.env)}"

# Log in to Amazon ECR so the host can pull the image during ApplicationStart
ACCOUNT_ID="$(/usr/bin/aws sts get-caller-identity --query Account --output text)"
ECR_HOST="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
/usr/bin/aws ecr get-login-password --region "$AWS_REGION" \
  | /usr/bin/docker login --username AWS --password-stdin "$ECR_HOST"

echo "=== [BeforeInstall] done ==="

# fi

# echo "=== [BeforeInstall] $(date -Is) finished OK ==="
# exit 0
