#!/usr/bin/env bash
#MISE description="Lint the Noora web package"
#USAGE flag "-f --fix" help="Fix fixable issues"
set -eo pipefail
cd noora
if [ "$usage_fix" = "true" ]; then
  mix format; pnpm prettier --write "js/**/*.js" "css/**/*.css"
else
  mix format --check-formatted; pnpm prettier --check "js/**/*.js" "css/**/*.css"
fi
