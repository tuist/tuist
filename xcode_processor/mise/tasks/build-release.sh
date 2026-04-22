#!/usr/bin/env bash
#MISE description "Build a production release (NIF + Elixir)"
#MISE depends=["build-nif"]
#MISE raw=true
set -euo pipefail

release_dir() {
    if [ -n "${TUIST_MIX_BUILD_ROOT:-}" ]; then
        printf '%s\n' "${TUIST_MIX_BUILD_ROOT}/xcode_processor/prod/rel/xcode_processor"
    else
        printf '%s\n' "_build/prod/rel/xcode_processor"
    fi
}

echo "==> Building Elixir release..."
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix release --overwrite

echo "==> Release built at $(release_dir)/"
