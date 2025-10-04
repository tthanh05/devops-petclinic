# #!/bin/bash
# set -euo pipefail
# echo "=== [ApplicationStart] $(date -Is) ==="

# REV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# set -a
# . "$REV_ROOT/release.env"
# set +a

# ECR_HOST="${IMAGE_REPO%%/*}"

# # ECR login using the instance role
# aws ecr get-login-password --region "$AWS_REGION" \
# | docker login --username AWS --password-stdin "$ECR_HOST" >/dev/null

# # Choose image ref
# IMAGE_REF="${IMAGE_REPO}:${IMAGE_TAG}"
# if [[ "${IMAGE_DIGEST:-}" =~ @sha256:[0-9a-f]{64}$ ]]; then
#   IMAGE_REF="$IMAGE_DIGEST"
# fi
# echo "Using image: $IMAGE_REF"

# export IMAGE_REF
# docker compose --env-file "$REV_ROOT/release.env" -f "$REV_ROOT/docker-compose.prod.yml" pull app || true
# docker compose --env-file "$REV_ROOT/release.env" -f "$REV_ROOT/docker-compose.prod.yml" up -d

# # ---- Monitoring stack (Prometheus + Alertmanager [+Grafana]) ----
# MON_DIR="$APP_DIR/monitoring"
# if [ -d "$MON_DIR" ]; then
#   echo "Starting monitoring stack..."
#   # Pass Slack webhook securely via env var file if present
#   if [ -f "$APP_DIR/monitoring.env" ]; then
#     set -a; source "$APP_DIR/monitoring.env"; set +a
#   fi
#   /usr/bin/docker compose -f "$MON_DIR/docker-compose.monitor.yml" up -d
# else
#   echo "Monitoring stack not found; skipping."
# fi

# sleep 5

# echo "=== [ApplicationStart] done ==="
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
/usr/bin/docker compose --env-file "$REV_ROOT/release.env" -f "$REV_ROOT/docker-compose.prod.yml" pull app || true
/usr/bin/docker compose --env-file "$REV_ROOT/release.env" -f "$REV_ROOT/docker-compose.prod.yml" up -d

# ---- Monitoring stack (Prometheus + Alertmanager [+Grafana]) ----
MON_DIR="$REV_ROOT/monitoring"   # <<— use the bundle path, not $APP_DIR
if [ -d "$MON_DIR" ]; then
  echo "Starting monitoring stack..."
  if [ -f "$REV_ROOT/monitoring.env" ]; then
    set -a; source "$REV_ROOT/monitoring.env"; set +a
  fi
  /usr/bin/docker compose -f "$MON_DIR/docker-compose.monitor.yml" up -d
else
  echo "Monitoring stack not found; skipping."
fi

sleep 5
echo "=== [ApplicationStart] done ==="

