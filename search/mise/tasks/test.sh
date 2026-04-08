#!/usr/bin/env bash
#MISE description "Build Docker image and verify TypeSense starts healthy"
#MISE raw=true
set -euo pipefail

IMAGE_NAME="tuist/search:test"
CONTAINER_NAME="search-test-$$"

cleanup() { docker rm -f "$CONTAINER_NAME" 2>/dev/null || true; }
trap cleanup EXIT

echo "Building Docker image..."
docker build -t "$IMAGE_NAME" .

echo "Starting container..."
docker run -d --name "$CONTAINER_NAME" \
  -e TYPESENSE_API_KEY=test \
  -e TYPESENSE_DATA_DIR=/data \
  -e TYPESENSE_ENABLE_CORS=true \
  -p 18108:8108 \
  "$IMAGE_NAME"

for i in $(seq 1 30); do
  if curl -sf http://localhost:18108/health > /dev/null 2>&1; then
    echo "Health check passed"
    exit 0
  fi
  sleep 1
done

echo "Health check failed"
docker logs "$CONTAINER_NAME"
exit 1
