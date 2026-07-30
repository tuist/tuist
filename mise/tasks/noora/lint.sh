#!/usr/bin/env bash
#MISE description="Lint the Noora web package"
#USAGE flag "-f --fix" help="Fix fixable issues"
set -eo pipefail
cd noora
if [ "$usage_fix" = "true" ]; then
  aube run generate:web-components
  mix format
  aube exec prettier --write "js/**/*.js" "css/**/*.css"
else
  aube run check:generated
  mix format --check-formatted
  aube exec prettier --check "js/**/*.js" "css/**/*.css"
fi
