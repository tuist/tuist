#!/usr/bin/env bash
# MISE description="Bring up a per-shard Tuist cluster for the CLI acceptance tests."
# MISE usage="<shard-index>"
#
# Each acceptance-test shard runs its own cluster so they don't fight over Postgres /
# ClickHouse / MinIO / port 8080. The shard index is folded into:
#
#   * COMPOSE_PROJECT_NAME (tuist-acceptance-${shard}) so volumes/networks are namespaced
#   * TUIST_CLUSTER_HOST_PORT (8080 + shard * 10) so multiple clusters can coexist
#
# Required env:
#   TUIST_IMAGE_TAG           — image tag under ghcr.io/tuist/tuist (defaults to `latest`)
# Optional env (CI uses these to log in to GHCR before pulling):
#   GITHUB_ACTOR / GITHUB_TOKEN
#
# After the cluster is healthy the script runs `Tuist.Release.seed` once via a one-shot
# container so the default `tuistrocks@tuist.dev` user exists.

set -euo pipefail

SHARD="${1:-0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CLUSTER_DIR="$ROOT_DIR/cli/cluster"

export COMPOSE_PROJECT_NAME="tuist-acceptance-${SHARD}"
export TUIST_CLUSTER_HOST_PORT="$((8080 + SHARD * 10))"
export TUIST_IMAGE_TAG="${TUIST_IMAGE_TAG:-latest}"

# Ensure docker + colima + docker-compose are available; skip on Linux where the
# Docker daemon is already provided by the runner.
mise install colima@latest docker-cli@latest docker-compose@latest >/dev/null

if [[ "$(uname -s)" == "Darwin" ]]; then
  if ! mise x colima@latest -- colima status >/dev/null 2>&1; then
    echo "Starting colima…"
    mise x colima@latest -- colima start --cpu 4 --memory 8 --disk 30
  fi
fi

# Log in to GHCR when CI creds are available so the pull can hit the private registry.
if [[ -n "${GITHUB_ACTOR:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
  echo "$GITHUB_TOKEN" | mise x docker-cli@latest -- docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin >/dev/null
fi

echo "Bringing up cluster '${COMPOSE_PROJECT_NAME}' on port ${TUIST_CLUSTER_HOST_PORT} (image: ghcr.io/tuist/tuist:${TUIST_IMAGE_TAG})"

mise x docker-compose@latest -- docker-compose -f "$CLUSTER_DIR/docker-compose.yml" up -d --wait postgres clickhouse minio minio-init tuist
mise x docker-compose@latest -- docker-compose -f "$CLUSTER_DIR/docker-compose.yml" run --rm tuist-seed

echo "Cluster '${COMPOSE_PROJECT_NAME}' ready at http://localhost:${TUIST_CLUSTER_HOST_PORT}"
