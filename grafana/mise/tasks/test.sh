#!/usr/bin/env bash
#MISE description="Test the Tuist Grafana app plugin"
set -euo pipefail
cd grafana
pnpm install --prefer-offline
pnpm run typecheck
pnpm run test:ci
