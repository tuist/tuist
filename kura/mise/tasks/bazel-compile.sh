#!/usr/bin/env bash
#MISE description="Build all kura targets for the host platform (bazel build //...); pass extra bazel flags through, e.g. mise run bazel-compile -- -c opt"
set -euo pipefail

# Build for the RUNNING platform: Bazel uses the autodetected host cc/rust toolchain
# (macOS or Linux native). The other release arch is built the same way on a runner of
# that arch — each arch is compiled natively, never cross-compiled.
#
# --remote_local_fallback degrades to local execution if the remote cache is unavailable, so a
# Tuist outage can't fail the build; it is a no-op when no remote cache is configured.
#
# No `cd` needed: mise runs file tasks from the config root (kura/), where the bazel workspace
# resolves.
bazel build //... --remote_local_fallback "$@"

echo "✔ kura binary: $(pwd)/bazel-bin/kura"
