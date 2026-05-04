#!/usr/bin/env bash
#MISE description="Lint the Tuist Grafana app plugin"
#USAGE flag "-f --fix" help="Fix fixable issues"
set -euo pipefail
if [ "${usage_fix:-false}" = "true" ]; then
  pnpm run lint:fix
else
  pnpm run lint
fi
