#!/usr/bin/env bash
#
# Run the Bazel shadow-CI validation locally, in the Linux dev container, against the
# host's native arch — so the whole flow (binaries + `bazel test` + the OCI image + e2e)
# can be validated without waiting for the GitHub `kura-bazel.yml` run.
#
# Unlike CI, this run dogfoods Kura itself as the Bazel **remote cache**: a single Kura
# node runs in a container on a shared Docker network, and the dev/build container points
# `bazel --remote_cache=grpc://...` at it. All action caching goes through Kura (the local
# `--disk_cache` is intentionally NOT used here, so warm reads genuinely exercise Kura's
# REAPI surface). `--repository_cache` stays — it caches *downloaded inputs* (crate
# sources, the geoip dump), which Kura's REAPI action cache does not serve.
#
# Chicken-and-egg: the Kura we run as the cache is a published server image
# (KURA_REMOTE_IMAGE), NOT a Bazel-built artifact — so the cache exists before we build the
# thing it caches. The default pins ghcr.io/esnunes/kura-fixed:cache, a patched arm64 build
# carrying the REAPI ByteStream flush fix (PR #11129) — without it, cargo build scripts
# (e.g. librocksdb-sys) never remote-cache and recompile every run. Once #11129 merges and
# the official image rebuilds, revert this to ghcr.io/tuist/kura:latest. Override
# KURA_REMOTE_IMAGE to pin any other tag.
#
# Kura's node storage (KURA_DATA_DIR) is bind-mounted to a host folder (KURA_DATA_HOST,
# default ~/.cache/kura-bazel-remote-cache) so the cache survives across runs. The cache
# *container* is started fresh and torn down at the end of each run; the *data* persists.
#
# On an Apple-silicon Mac this exercises the arm64-host path end to end:
#   - arm64-native + x86_64-cross binaries and `bazel test` (bazel/ci-validate.sh)
#   - the OCI image: native (arm64) tarball + the multi-arch index (bazel/ci-oci.sh)
#   - `docker load` + smoke + the `spec/e2e/cluster_spec.sh` suite against the image
# The x86_64-HOST native path (running x86_64 binaries/images natively) needs an x86_64
# machine, so that leg stays CI-only.
#
# Environment overrides:
#   KURA_REMOTE_IMAGE   server image to run as the cache
#                       (default ghcr.io/esnunes/kura-fixed:cache — patched, see note above)
#   KURA_REMOTE_PULL    "always" to re-pull the image each run; default pulls only if absent
#   KURA_DATA_HOST      host folder for Kura's persistent node storage
#   KURA_BAZEL_NETWORK  shared Docker network name (default kura-bazel-net)
#   KURA_HOST_GRPC_PORT / KURA_HOST_HTTP_PORT   host ports published for the cache (debug)
#
# Usage:  bazel/local-ci.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="kura-bazel-dev"
case "$(uname -m)" in
  arm64 | aarch64) ARCH=arm64 ;;
  x86_64 | amd64) ARCH=amd64 ;;
  *) echo "unsupported host arch: $(uname -m)" >&2; exit 1 ;;
esac
# Holds Bazel's output base + --repository_cache (downloaded crate sources, geoip). The
# action cache lives in Kura now, not in this volume.
REPO_CACHE_VOLUME="kura-bazel-cache-${ARCH}"

# Kura remote-cache settings (all overridable).
KURA_REMOTE_IMAGE="${KURA_REMOTE_IMAGE:-ghcr.io/esnunes/kura-fixed:cache}"
NETWORK="${KURA_BAZEL_NETWORK:-kura-bazel-net}"
CACHE_CONTAINER="${KURA_CACHE_CONTAINER:-kura-bazel-remote-cache}"
KURA_DATA_HOST="${KURA_DATA_HOST:-$HOME/.cache/kura-bazel-remote-cache}"
KURA_GRPC_PORT_INTERNAL=50051
KURA_HTTP_PORT_INTERNAL=4000
KURA_HOST_GRPC_PORT="${KURA_HOST_GRPC_PORT:-5599}"
KURA_HOST_HTTP_PORT="${KURA_HOST_HTTP_PORT:-4599}"
# The dev/build container reaches Kura by container name over the shared network.
REMOTE_CACHE_URL="grpc://${CACHE_CONTAINER}:${KURA_GRPC_PORT_INTERNAL}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "==> building dev image $IMAGE"
  docker build -f "$REPO_ROOT/bazel/linux-dev.Dockerfile" -t "$IMAGE" "$REPO_ROOT"
fi

stop_remote_cache() {
  docker rm -f "$CACHE_CONTAINER" >/dev/null 2>&1 || true
}

start_remote_cache() {
  stop_remote_cache
  mkdir -p "$KURA_DATA_HOST"
  docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null

  if [ "${KURA_REMOTE_PULL:-missing}" = "always" ] \
    || ! docker image inspect "$KURA_REMOTE_IMAGE" >/dev/null 2>&1; then
    echo "==> pulling $KURA_REMOTE_IMAGE"
    if ! docker pull "$KURA_REMOTE_IMAGE"; then
      echo "Failed to pull $KURA_REMOTE_IMAGE." >&2
      echo "If it is private, run 'docker login ghcr.io', or set KURA_REMOTE_IMAGE to an accessible tag/local image." >&2
      exit 1
    fi
  fi

  echo "==> starting Kura remote cache ($CACHE_CONTAINER) on network $NETWORK"
  echo "    data dir (persistent): $KURA_DATA_HOST"
  docker run -d --name "$CACHE_CONTAINER" --network "$NETWORK" \
    -p "${KURA_HOST_HTTP_PORT}:${KURA_HTTP_PORT_INTERNAL}" \
    -p "${KURA_HOST_GRPC_PORT}:${KURA_GRPC_PORT_INTERNAL}" \
    -e KURA_PORT="$KURA_HTTP_PORT_INTERNAL" \
    -e KURA_GRPC_PORT="$KURA_GRPC_PORT_INTERNAL" \
    -e KURA_INTERNAL_PORT=7443 \
    -e KURA_TENANT_ID=default \
    -e KURA_REGION=local \
    -e KURA_NODE_URL="http://${CACHE_CONTAINER}:7443" \
    -e KURA_DATA_DIR=/var/cache/kura \
    -e KURA_TMP_DIR=/tmp/kura \
    -e KURA_OTEL_SERVICE_NAME=kura-local-ci \
    -e KURA_OTEL_DEPLOYMENT_ENVIRONMENT=local \
    -e RUST_LOG="${KURA_RUST_LOG:-info}" \
    -v "$KURA_DATA_HOST:/var/cache/kura" \
    "$KURA_REMOTE_IMAGE" >/dev/null
}

wait_for_remote_cache() {
  echo "==> waiting for Kura remote cache"
  local i
  for i in $(seq 1 60); do
    if curl -fsS "http://localhost:${KURA_HOST_HTTP_PORT}/up" >/dev/null 2>&1; then
      echo "    up: $REMOTE_CACHE_URL  (host debug: http://localhost:${KURA_HOST_HTTP_PORT})"
      return 0
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx "$CACHE_CONTAINER"; then
      echo "Kura cache container exited unexpectedly:" >&2
      docker logs "$CACHE_CONTAINER" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "Kura remote cache did not become ready in time" >&2
  docker logs "$CACHE_CONTAINER" >&2 || true
  return 1
}

# Run a command in the dev container, joined to the shared network so it can reach the
# Kura cache by name, and — like CI does via /root/.bazelrc — point Bazel at the remote
# cache. The action cache lives entirely in Kura now (no --disk_cache). --repository_cache
# stays in the mounted volume so crate/geoip downloads are reused across runs, and
# --remote_download_outputs=all forces all outputs to materialize locally (ci-validate.sh
# installs the binary off disk and ci-oci.sh copies the tarball off bazel-bin/).
#
# --http_timeout_scaling=8 widens Bazel's per-attempt download connect/read timeouts.
# GitHub's release CDN (rules_rust/platforms/etc. on the cold-fetch repository phase) is
# intermittently slow to connect from some networks; Bazel already retries (5x) but the
# default timeout is tight enough that a slow SYN-ACK surfaces as "Connect timed out" and
# fails the whole run. Only bites the first cold fetch — once the repository_cache volume
# is warm, deps are not re-fetched.
in_container() {
  docker run --rm \
    --network "$NETWORK" \
    -e KURA_LOCAL_CI_REMOTE_CACHE="$REMOTE_CACHE_URL" \
    -v "$REPO_ROOT:/workspace/kura" \
    -v "$REPO_CACHE_VOLUME:/root/.cache/bazel" \
    "$IMAGE" bash -c '
      mkdir -p /root/.cache/bazel/repo
      {
        echo "common --repository_cache=/root/.cache/bazel/repo"
        echo "common --http_timeout_scaling=8"
        echo "common --remote_cache=${KURA_LOCAL_CI_REMOTE_CACHE}"
        echo "common --remote_instance_name=kura-local-ci"
        echo "common --remote_upload_local_results=true"
        echo "common --remote_download_outputs=all"
      } > /root/.bazelrc
      exec "$@"' _ "$@"
}

# Retry a step on transient failure. GitHub's release CDN intermittently fails cold-phase
# repository fetches (connect timeouts, 504s); a 504 in particular is a server blip that
# timeout tuning can't fix. Each retry reuses the persistent repository cache, so only the
# repo that flaked is re-fetched — the step resumes rather than restarting from scratch.
retry() {
  local attempt=1 max=4
  while true; do
    if "$@"; then return 0; fi
    if [ "$attempt" -ge "$max" ]; then
      echo "    step failed after $max attempts" >&2
      return 1
    fi
    echo "    attempt $attempt failed (likely a transient GitHub CDN fetch); retrying in $((attempt * 10))s..." >&2
    sleep "$((attempt * 10))"
    attempt=$((attempt + 1))
  done
}

trap stop_remote_cache EXIT
start_remote_cache
wait_for_remote_cache

echo "==> [1/4] binaries + bazel test (ci-validate.sh)"
retry in_container bash bazel/ci-validate.sh

echo "==> [2/4] OCI image: native tarball + multi-arch index (ci-oci.sh)"
retry in_container bash bazel/ci-oci.sh

echo "==> [3/4] load native image + smoke test"
docker load -i "$REPO_ROOT/bazel-dist/kura-oci.tar"
smoke="$(docker run --rm kura-bazel:oci 2>&1 || true)"
if ! echo "$smoke" | grep -q "invalid configuration"; then
  echo "smoke FAILED: image did not start cleanly under tini" >&2
  echo "$smoke" >&2
  exit 1
fi
echo "    smoke OK (starts under tini, exits on missing config as expected)"

echo "==> [4/4] e2e (cluster_spec) against the Bazel image"
(
  cd "$REPO_ROOT"
  KURA_IMAGE=kura-bazel:oci KURA_E2E_SKIP_BUILD=1 mise exec -- shellspec spec/e2e/cluster_spec.sh
)

echo
echo "Local validation passed (native $ARCH): binaries + bazel test + OCI image + e2e."
echo "Action caching ran through Kura at $REMOTE_CACHE_URL (data persisted in $KURA_DATA_HOST)."
echo "The x86_64-HOST native path remains CI-only."
