#!/usr/bin/env bash
#MISE description="Test the Tuist Grafana app plugin"
set -euo pipefail
cd grafana
npm install --no-audit --no-fund
npm run typecheck
npm run test:ci
