#!/usr/bin/env bash
#
# Run the Bazel shadow-CI validation locally, in the Linux dev container, against the
# host's native arch — so the whole flow (binaries + `bazel test` + the OCI image + e2e)
# can be validated without waiting for the GitHub `kura-bazel.yml` run.
#
# On an Apple-silicon Mac this exercises the arm64-host path end to end:
#   - arm64-native + x86_64-cross binaries and `bazel test` (bazel/ci-validate.sh)
#   - the OCI image: native (arm64) tarball + the multi-arch index (bazel/ci-oci.sh)
#   - `docker load` + smoke + the `spec/e2e/cluster_spec.sh` suite against the image
# The x86_64-HOST native path (running x86_64 binaries/images natively) needs an x86_64
# machine, so that leg stays CI-only.
#
# Reuses the persistent per-arch Bazel cache volume, so re-runs are incremental (the
# native -sys crates are not recompiled). Same scripts the CI jobs run, so local == CI.
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
CACHE="kura-bazel-cache-${ARCH}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "==> building dev image $IMAGE"
  docker build -f "$REPO_ROOT/bazel/linux-dev.Dockerfile" -t "$IMAGE" "$REPO_ROOT"
fi

in_container() {
  docker run --rm \
    -v "$REPO_ROOT:/workspace/kura" \
    -v "$CACHE:/root/.cache/bazel" \
    "$IMAGE" "$@"
}

echo "==> [1/4] binaries + bazel test (ci-validate.sh)"
in_container bash bazel/ci-validate.sh

echo "==> [2/4] OCI image: native tarball + multi-arch index (ci-oci.sh)"
in_container bash bazel/ci-oci.sh

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
echo "The x86_64-HOST native path remains CI-only."
