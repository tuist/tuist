#!/usr/bin/env bash
# Phase 4c: run a Kura node as the Bazel remote cache in CI (kura-bazel.yml), mirroring
# bazel/local-ci.sh's remote-cache wiring but parameterized for the GitHub Actions runner.
#
# The node's data dir (KURA_DATA_DIR) is a host path that the workflow persists with
# actions/cache — so the *action* cache lives in Kura's on-disk format (the same surface a
# production Kura-backed cache would use), not in Bazel's --disk_cache. Bazel's
# --repository_cache (downloaded crate sources, geoip) is persisted separately by the
# workflow because Kura's REAPI does not serve downloaded inputs.
#
# Chicken-and-egg (intentional, see the migration plan): the cache is the published server
# image, not a Bazel-built artifact, so it exists before we build the thing it caches.
#
# Usage:
#   KURA_CI_DATA_DIR=<host dir> bazel/ci-kura-cache.sh start   # boot node, wait for /up
#   KURA_CI_DATA_DIR=<host dir> bazel/ci-kura-cache.sh stop    # tear down, surface errors,
#                                                              # make data dir cache-readable
# The build container reaches the node by container name over $KURA_CI_NETWORK:
#   common --remote_cache=grpc://${KURA_CI_CONTAINER}:${KURA_CI_GRPC_PORT}
set -euo pipefail

CMD="${1:-}"
NETWORK="${KURA_CI_NETWORK:-kura-bazel-ci-net}"
CONTAINER="${KURA_CI_CONTAINER:-kura-bazel-ci-cache}"
IMAGE="${KURA_CACHE_IMAGE:-ghcr.io/tuist/kura:latest}"
DATA_DIR="${KURA_CI_DATA_DIR:?set KURA_CI_DATA_DIR to the host path persisted by actions/cache}"
HTTP_PORT="${KURA_CI_HTTP_PORT:-4599}"
GRPC_PORT="${KURA_CI_GRPC_PORT:-50051}"
# Kura's FD pool must absorb Bazel's bursty concurrent blob uploads (a cargo build script
# with a large directory output — librocksdb-sys emits ~339 .o files — uploads them in
# parallel via ByteStream). With the default pool the permits exhaust, writes fail with
# "fd_pool_exhausted", the action result is never stored, and that crate recompiles every
# run. Size it generously and raise the container nofile ceiling to match (#11132).
FD_POOL="${KURA_FD_POOL:-4096}"
NOFILE="${KURA_NOFILE:-16384}"

case "$CMD" in
  start)
    mkdir -p "$DATA_DIR"
    docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    echo "==> pulling $IMAGE"
    docker pull "$IMAGE"
    echo "==> starting Kura remote cache ($CONTAINER) on $NETWORK; data dir: $DATA_DIR"
    docker run -d --name "$CONTAINER" --network "$NETWORK" \
      --ulimit "nofile=${NOFILE}:${NOFILE}" \
      -p "127.0.0.1:${HTTP_PORT}:4000" \
      -e KURA_FILE_DESCRIPTOR_POOL_SIZE="$FD_POOL" \
      -e KURA_PORT=4000 \
      -e KURA_GRPC_PORT="$GRPC_PORT" \
      -e KURA_INTERNAL_PORT=7443 \
      -e KURA_TENANT_ID=default \
      -e KURA_REGION=ci \
      -e KURA_NODE_URL="http://${CONTAINER}:7443" \
      -e KURA_DATA_DIR=/var/cache/kura \
      -e KURA_TMP_DIR=/tmp/kura \
      -e KURA_OTEL_SERVICE_NAME=kura-bazel-ci \
      -e KURA_OTEL_DEPLOYMENT_ENVIRONMENT=ci \
      -e RUST_LOG="${KURA_RUST_LOG:-warn}" \
      -v "${DATA_DIR}:/var/cache/kura" \
      "$IMAGE" >/dev/null
    for _ in $(seq 1 60); do
      if curl -fsS "http://127.0.0.1:${HTTP_PORT}/up" >/dev/null 2>&1; then
        echo "    up: grpc://${CONTAINER}:${GRPC_PORT}"
        exit 0
      fi
      if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        echo "Kura cache container exited unexpectedly:" >&2
        docker logs "$CONTAINER" >&2 || true
        exit 1
      fi
      sleep 1
    done
    echo "Kura remote cache did not become ready in time" >&2
    docker logs "$CONTAINER" >&2 || true
    exit 1
    ;;
  stop)
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
      # Surface the defects that silently break caching of directory outputs: the ByteStream
      # flush race (#11129, fixed) and FD-pool exhaustion (#11132). A non-zero count means
      # the comparison numbers are not trustworthy — warn loudly but don't fail the shadow job.
      n="$(docker logs "$CONTAINER" 2>&1 | grep -Eic 'fd_pool_exhausted|failed to persist|appended .* expected' || true)"
      echo "Kura cache persist/fd error lines: ${n:-0}"
      if [ "${n:-0}" -gt 0 ]; then
        echo "::warning title=Kura remote cache errors::${n} persist/fd error line(s) — cache likely incomplete, build-time comparison unreliable"
      fi
      docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    fi
    # Kura writes the data dir as the container user; make it readable to the runner user so
    # actions/cache can archive it.
    if [ -d "$DATA_DIR" ]; then
      sudo chmod -R a+rX "$DATA_DIR" 2>/dev/null || chmod -R a+rX "$DATA_DIR" 2>/dev/null || true
    fi
    ;;
  *)
    echo "usage: $0 {start|stop}" >&2
    exit 2
    ;;
esac
