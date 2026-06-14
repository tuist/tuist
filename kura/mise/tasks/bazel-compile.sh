#!/usr/bin/env bash
#MISE description="Compile the kura binary for the host platform (bazel build //:kura -c opt; pass extra bazel flags through, e.g. mise run bazel-compile -- -c dbg)"
set -euo pipefail

# Build for the RUNNING platform: no --platforms, so Bazel uses the autodetected host cc/rust
# toolchain (macOS or Linux native) — no cross-GCC dev container needed. Cross builds for the
# other arch go through --platforms (see the CI compile/oci jobs).
#
# No `cd` needed: mise runs file tasks from the config root (kura/), where the bazel workspace
# resolves.
bazel build //:kura -c opt "$@"

echo "✔ kura binary: $(pwd)/bazel-bin/kura"
