#!/usr/bin/env bash
#MISE description="Run the formatters"
#USAGE flag "-c --check" help="It checks without formatting, failing if the checks fail"

if [ "$usage_check" = "true" ]; then
  (cd server && mix format --check-formatted)
  prettier -c server/priv/static/app
  prettier -c server/assets
else
  (cd server && mix format)
  prettier --write server/priv/static/app
  prettier --write server/assets
fi
