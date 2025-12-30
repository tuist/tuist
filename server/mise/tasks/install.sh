#!/bin/bash
#MISE description="Install all necessary dependencies"

set -euo pipefail

mix deps.get
pnpm install --ignore-workspace

if [ -z "${CI:-}" ]; then
  mise run db:reset
fi
