#!/bin/bash
#MISE description="Install all necessary dependencies"

set -eo pipefail

mix deps.get
pnpm install --ignore-workspace
pnpm install -C ./worker/

if [ -z "$CI" ]; then
  mise run db:reset
fi
