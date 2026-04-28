#!/usr/bin/env bash
#MISE description "Build the macOS Tuist server release for the xcresult-processor role"
#MISE depends=["build-nif"]
#MISE raw=true
set -euo pipefail

# The xcresult processor is the *server* release boot in xcresult-processor
# mode (TUIST_XCRESULT_PROCESSOR_MODE=1) on a macOS host. Same codebase as
# the in-cluster Linux pods, same Ecto schemas, same priv/secrets/<env>.yml.enc
# — only the Oban queue list differs at runtime, and only the macOS-specific
# xcresult NIF is loaded. We don't ship a separate Elixir app; that means
# the Mac mini's release output stays bit-for-bit aligned with what enqueued
# the job, exactly like the build-processor consolidation in #10428.
#
# The xcactivitylog NIF is Linux-only (built via the server Dockerfile's
# Swift-on-Linux stage). We don't try to build it on macOS — its Elixir
# wrapper tolerates a missing .so at boot when not running on Linux, and
# the macOS pod never claims `:process_build` so the parse path is never
# exercised.

REPO_ROOT="$(git rev-parse --show-toplevel)"
SERVER_DIR="${REPO_ROOT}/server"

release_dir() {
    if [ -n "${TUIST_MIX_BUILD_ROOT:-}" ]; then
        printf '%s\n' "${TUIST_MIX_BUILD_ROOT}/server/prod/rel/tuist"
    else
        printf '%s\n' "${SERVER_DIR}/_build/prod/rel/tuist"
    fi
}

cd "${SERVER_DIR}"

echo "==> Fetching prod deps..."
MIX_ENV=prod mix deps.get --only prod

echo "==> Compiling server (MIX_ENV=prod)..."
MIX_ENV=prod mix compile

echo "==> Building server release..."
MIX_ENV=prod mix release --overwrite

echo "==> Release built at $(release_dir)/"
