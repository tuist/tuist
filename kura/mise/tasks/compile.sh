#!/usr/bin/env bash
#MISE description="Build all kura targets for the host platform (bazel build //...); pass extra bazel flags through, e.g. mise run compile -- -c opt"
set -euo pipefail

# No `cd` needed: mise runs file tasks from the config root (kura/), where the bazel workspace
# resolves.
bazel build //... "$@"

echo "✔ kura binary: $(pwd)/bazel-bin/kura"
