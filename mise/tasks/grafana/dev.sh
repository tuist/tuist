#!/usr/bin/env bash
#MISE description="Run the Tuist Grafana app plugin in watch mode against a local Grafana container"
set -euo pipefail
cd grafana
pnpm install --prefer-offline
pnpm run dev &
WEBPACK_PID=$!
trap 'kill $WEBPACK_PID 2>/dev/null || true' EXIT

docker run --rm \
  -p 3000:3000 \
  -e GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-tuist-app \
  -v "$PWD/dist:/var/lib/grafana/plugins/tuist-tuist-app" \
  grafana/grafana:latest
