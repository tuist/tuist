#!/usr/bin/env bash
#MISE description="Run Grafana + Prometheus locally with the plugin scraping staging.tuist.dev"
set -euo pipefail

cd "${MISE_PROJECT_ROOT}"

if [ -z "${TUIST_METRICS_TOKEN:-}" ]; then
  echo "ERROR: TUIST_METRICS_TOKEN is not set." >&2
  echo "       Mint a token with the account:metrics:read scope, store it in 1Password," >&2
  echo "       and export it before running this task:" >&2
  echo "" >&2
  echo "       export TUIST_METRICS_TOKEN=\"\$(op read 'op://Shared/Tuist Grafana plugin — staging/credential')\"" >&2
  exit 1
fi

# Materialise the token as a short-lived file that docker-compose mounts
# read-only into the Prometheus container. Never logged, never committed.
mkdir -p .secrets
umask 077
printf '%s' "${TUIST_METRICS_TOKEN}" > .secrets/tuist-metrics-token
umask 022

# Install + build the plugin so dist/ exists before docker-compose mounts it.
pnpm install --ignore-workspace --prefer-offline
export TS_NODE_TRANSPILE_ONLY=true
export TS_NODE_FILES=true
pnpm run build

pnpm run dev &
WEBPACK_PID=$!

cleanup() {
  kill $WEBPACK_PID 2>/dev/null || true
  docker compose down --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

docker compose up --force-recreate
