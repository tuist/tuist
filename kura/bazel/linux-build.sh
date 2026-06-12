#!/usr/bin/env bash
#
# Run a Bazel command against Linux (Debian Bookworm) inside a container, from a
# macOS host. Bazel's cache persists in a per-arch named Docker volume so re-runs
# are incremental. See docs/bazel-migration-plan.md.
#
# Arch defaults to the host's; set KURA_ARCH=amd64 or arm64 to pick. amd64 on an
# Apple-silicon host runs under emulation (slow first build) — it mirrors what the
# x86_64 CI runner does natively.
#
# Usage:   bazel/linux-build.sh build //:kura
#          KURA_ARCH=amd64 bazel/linux-build.sh build //:kura
set -euo pipefail

ARCH="${KURA_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64 | aarch64) ARCH=arm64 ;;
  amd64 | x86_64) ARCH=amd64 ;;
  *) echo "unsupported KURA_ARCH: $ARCH (use amd64 or arm64)" >&2; exit 1 ;;
esac

PLATFORM="linux/${ARCH}"
IMAGE="kura-bazel-linux-${ARCH}"
CACHE="kura-bazel-cache-${ARCH}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Build the dev image if it's missing (cheap once cached).
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build --platform "$PLATFORM" -f "$REPO_ROOT/bazel/linux-dev.Dockerfile" -t "$IMAGE" "$REPO_ROOT"
fi

exec docker run --rm --platform "$PLATFORM" \
  -v "$REPO_ROOT":/workspace/kura \
  -v "$CACHE":/root/.cache/bazel \
  "$IMAGE" \
  bazel "$@"
