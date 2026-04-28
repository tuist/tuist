#!/usr/bin/env bash
# MISE description="Tear down a per-shard Tuist cluster previously brought up by up.sh."
# MISE usage="<shard-index>"

set -euo pipefail

SHARD="${1:-0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CLUSTER_DIR="$ROOT_DIR/cli/cluster"

export COMPOSE_PROJECT_NAME="tuist-acceptance-${SHARD}"
export TUIST_CLUSTER_HOST_PORT="$((8080 + SHARD * 10))"
export TUIST_IMAGE_TAG="${TUIST_IMAGE_TAG:-latest}"

docker compose -f "$CLUSTER_DIR/docker-compose.yml" down -v --remove-orphans
