#!/usr/bin/env bash
#MISE description="Run the formatters"
#USAGE flag "-c --check" help="It checks without formatting, failing if the checks fail"

if [ "$usage_check" = "true" ]; then
  (cd $MISE_PROJECT_ROOT && mix format --check-formatted)
  prettier -c $MISE_PROJECT_ROOT/priv/static/app
else
  (cd $MISE_PROJECT_ROOT && mix format)
  prettier --write $MISE_PROJECT_ROOT/priv/static/app
fi
