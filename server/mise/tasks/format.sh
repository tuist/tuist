#!/usr/bin/env bash
#MISE description="Run the formatters"
#USAGE flag "-c --check" help="It checks without formatting, failing if the checks fail"

set -euo pipefail

if [ "${usage_check:-}" = "true" ]; then
  mix format --check-formatted
  prettier -c priv/static/app
  prettier -c assets
else
  mix format
  prettier --write priv/static/app
  prettier --write assets
fi
