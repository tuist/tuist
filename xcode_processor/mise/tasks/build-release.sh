#!/usr/bin/env bash
#MISE description "Build a production release (NIF + Elixir)"
#MISE raw=true
set -euo pipefail

echo "==> Building Swift NIF..."
bash native/xcresult_nif/build.sh

echo "==> Building Elixir release..."
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix release --overwrite

echo "==> Release built at _build/prod/rel/xcode_processor/"
