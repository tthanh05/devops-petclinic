#!/bin/bash
set -euo pipefail
echo "=== [ApplicationStart] $(date -Is) ==="

REV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a
. "$REV_ROOT/release.env"
set +a

ECR_HOST="${IMAGE_REPO%%/*}"

# ECR login using the instance role
aws ecr get-login-password --region "$AWS_REGION" \
| docker login --username AWS --password-stdin "$ECR_HOST" >/dev/null

# Choose image ref
IMAGE_REF="${IMAGE_REPO}:${IMAGE_TAG}"
if [[ "${IMAGE_DIGEST:-}" =~ @sha256:[0-9a-f]{64}$ ]]; then
  IMAGE_REF="$IMAGE_DIGEST"
fi
echo "Using image: $IMAGE_REF"

export IMAGE_REF
docker compose --env-file "$REV_ROOT/release.env" -f "$REV_ROOT/docker-compose.prod.yml" pull app || true
docker compose --env-file "$REV_ROOT/release.env" -f "$REV_ROOT/docker-compose.prod.yml" up -d

echo "=== [ApplicationStart] done ==="
