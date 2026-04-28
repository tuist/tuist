#!/usr/bin/env bash
#MISE description "Build the xcresult Swift NIF for macOS into server/priv/native"
#MISE raw=true
set -euo pipefail

# Thin wrapper around server/native/xcresult_nif/build.sh — keeps the deploy
# pipeline's build step in one place even though the NIF source now lives
# alongside the server. The NIF's .so + .dylib end up in
# server/priv/native/, where `mix release` picks them up.

REPO_ROOT="$(git rev-parse --show-toplevel)"
exec "${REPO_ROOT}/server/native/xcresult_nif/build.sh"
