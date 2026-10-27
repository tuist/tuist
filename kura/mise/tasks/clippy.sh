#!/usr/bin/env bash
#MISE description="Lint all kura targets with clippy via Bazel (rules_rust clippy aspect; warnings are errors). Pass extra bazel flags through, e.g. mise run clippy -- -c opt. Fall back to cargo clippy only if Bazel is unavailable."
set -euo pipefail

# The aspect lints only the first-party //... targets (it doesn't propagate to the crate graph) and,
# given no explicit flags, treats warnings as errors — equivalent to the old
# `cargo clippy --all-targets -- -D warnings` gate.
bazel build //... \
  --aspects=@rules_rust//rust:defs.bzl%rust_clippy_aspect \
  --output_groups=clippy_checks \
  "$@"
