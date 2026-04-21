#!/usr/bin/env bash
#MISE description="Build the Tuist Grafana app plugin"
set -euo pipefail
cd grafana
pnpm install --prefer-offline
pnpm run build
