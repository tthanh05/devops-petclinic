#!/bin/bash
set -euo pipefail

echo "=== [BeforeInstall] $(date -Is) starting ==="

# Root of the extracted revision (parent of scripts/)
REV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load release variables that Jenkins packaged into the bundle
if [[ -f "$REV_ROOT/release.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$REV_ROOT/release.env"
  set +a
else
  echo "ERROR: $REV_ROOT/release.env not found"
  exit 1
fi

# Ensure required tools (best-effort)
command -v unzip >/dev/null 2>&1 || (yum -y install unzip || dnf -y install unzip || true)

# Normalize line endings of files we rely on (in case CRLF slipped in)
find "$REV_ROOT" -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.env' \) -exec sed -i 's/\r$//' {} +

# Prepare target directory for later hooks
APP_DIR="/opt/petclinic"
mkdir -p "$APP_DIR"

echo "Using region=${AWS_REGION:-unset}, image=${IMAGE_REPO:-unset}:${IMAGE_TAG:-unset}"
echo "=== [BeforeInstall] done ==="
