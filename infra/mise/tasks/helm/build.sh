#!/usr/bin/env bash
#MISE description="Build the Docker images for the local Helm deployment"

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

echo "==> Building tuist-server image..."
docker build \
    --target runner-selfhosted \
    --build-arg TUIST_HOSTED=0 \
    -t tuist-server:latest \
    -f "$REPO_ROOT/server/Dockerfile" \
    "$REPO_ROOT"

echo "==> Building tuist-cache image..."
docker build \
    -t tuist-cache:latest \
    -f "$REPO_ROOT/cache/Dockerfile" \
    "$REPO_ROOT"

echo "==> Done. Images built:"
docker images --filter reference=tuist-server --filter reference=tuist-cache --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
