#!/usr/bin/env bash
#MISE description="Compile the kura binary for the host platform (bazel build //:kura -c opt; pass extra bazel flags through, e.g. mise run bazel-compile -- -c dbg)"
set -euo pipefail

# Build for the RUNNING platform: Bazel uses the autodetected host cc/rust toolchain
# (macOS or Linux native). The other release arch is built the same way on a runner of
# that arch — each arch is compiled natively, never cross-compiled.
#
# No `cd` needed: mise runs file tasks from the config root (kura/), where the bazel workspace
# resolves.
bazel build //:kura -c opt "$@"

echo "✔ kura binary: $(pwd)/bazel-bin/kura"
