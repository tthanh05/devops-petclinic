#!/usr/bin/env bash
set -euo pipefail
APP_DIR="/opt/petclinic"
cd "$APP_DIR"

# Load release variables written by Jenkins
source ./release.env

# ECR login (region from release.env)
aws ecr get-login-password --region "${AWS_REGION:-ap-southeast-2}" \
  | docker login --username AWS --password-stdin "${IMAGE_REPO%/*}"

# Choose immutable digest if present, else fall back to tag
IMG="${IMAGE_DIGEST:-${IMAGE_REPO}:${IMAGE_TAG}}"

# Pull and start
docker pull "$IMG"
docker compose --env-file release.env -f docker-compose.prod.yml up -d --remove-orphans

echo "=== [ApplicationStart] $(date -Is) done ==="
