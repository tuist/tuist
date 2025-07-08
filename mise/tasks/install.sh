#!/bin/bash
# mise description="Install all necessary dependencies"

set -eo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

pnpm install
tuist install
(cd server && mix deps.get)
(cd server && pnpm install)

if [ -z "$CI" ]; then
  $SCRIPT_DIR/server/db/reset.sh
fi
