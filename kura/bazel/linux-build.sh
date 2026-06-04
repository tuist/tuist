#!/usr/bin/env bash
#
# Run a Bazel command against Linux (arm64, Debian Bookworm) inside the
# kura-bazel-linux container, from a macOS host. Bazel's cache persists in a
# named Docker volume so re-runs are incremental. See docs/bazel-migration-plan.md.
#
# Prereq:  docker build -f bazel/linux-dev.Dockerfile -t kura-bazel-linux .
# Usage:   bazel/linux-build.sh build @crates//:rocksdb
#          bazel/linux-build.sh test //...
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec docker run --rm \
  -v "$REPO_ROOT":/workspace/kura \
  -v kura-bazel-cache:/root/.cache/bazel \
  kura-bazel-linux \
  bazel "$@"
