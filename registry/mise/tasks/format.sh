#!/usr/bin/env bash
#MISE description="Run Elixir formatter"
#USAGE flag "-c --check" help="Check formatting without writing"
set -euo pipefail

if [ "${usage_check:-false}" = "true" ]; then
  mix format --check-formatted
else
  mix format
fi
