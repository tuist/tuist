#!/usr/bin/env bash
#MISE description="Build the Tuist Grafana app plugin"
set -euo pipefail
pnpm install --prefer-offline
pnpm run build
