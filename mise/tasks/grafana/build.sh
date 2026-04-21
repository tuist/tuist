#!/usr/bin/env bash
#MISE description="Build the Tuist Grafana app plugin"
set -euo pipefail
cd grafana
npm install --no-audit --no-fund
npm run build
