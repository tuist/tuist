#!/usr/bin/env bash
#MISE description="Format JavaScript files"
#USAGE flag "-c --check" help="Check formatting without modifying files"

set -euo pipefail

cd "$MISE_PROJECT_ROOT"

if [ "${usage_check:-}" = "true" ]; then
  pnpm exec prettier --check "src/**/*.js" "*.js"
else
  pnpm exec prettier --write "src/**/*.js" "*.js"
fi
