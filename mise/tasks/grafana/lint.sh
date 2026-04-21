#!/usr/bin/env bash
#MISE description="Lint the Tuist Grafana app plugin"
#USAGE flag "-f --fix" help="Fix fixable issues"
set -euo pipefail
cd grafana
npm install --no-audit --no-fund
if [ "${usage_fix:-false}" = "true" ]; then
  npm run lint:fix
else
  npm run lint
fi
