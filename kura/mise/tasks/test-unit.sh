#!/usr/bin/env bash
#MISE description="Run the kura unit tests via Bazel (bazel test //...; extra flags pass through, e.g. mise run test-unit -- --test_output=all). Fall back to cargo test only if Bazel is unavailable."
set -euo pipefail

# RocksDB-backed tests open many fds in parallel, so raise the soft limit. A warm Bazel server keeps
# the limit it was first started with, so run `bazel shutdown` if you change this and it doesn't take.
ulimit -n 65536

bazel test //... "$@"
