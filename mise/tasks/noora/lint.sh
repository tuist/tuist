#!/usr/bin/env bash
#MISE description="Lint the Noora web package"
#USAGE flag "-f --fix" help="Fix fixable issues"
set -eo pipefail
cd noora
if [ "$usage_fix" = "true" ]; then
  mix format; aube exec prettier --write "js/**/*.js" "css/**/*.css"
else
  mix format --check-formatted; aube exec prettier --check "js/**/*.js" "css/**/*.css"
fi
