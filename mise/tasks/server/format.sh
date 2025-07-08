#!/usr/bin/env bash
#MISE description="Run the formatters"
#USAGE flag "-c --check" help="It checks without formatting, failing if the checks fail"

if [ "$usage_check" = "true" ]; then
  (cd server && mix format --check-formatted)
  (cd server && prettier -c priv/static/app)
  (cd server && prettier -c assets)
else
  (cd server && mix format)
  (cd server && prettier --write priv/static/app)
  (cd server && prettier --write assets)
fi
