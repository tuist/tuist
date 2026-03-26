#!/bin/bash
#MISE description="Install all necessary dependencies"

set -euo pipefail

mix deps.get
pnpm install --ignore-workspace
pushd .. >/dev/null
pnpm install --filter noora
popd >/dev/null
pushd ../noora >/dev/null
pnpm run build
popd >/dev/null

if [ -z "${CI:-}" ]; then
  mise run db:reset
fi
