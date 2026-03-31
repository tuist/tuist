#!/usr/bin/env bash
#MISE description="Run the cache k6 load test"
#MISE raw=true
set -euo pipefail

: "${CACHE_AUTH_TOKEN:?CACHE_AUTH_TOKEN must be set}"
: "${CACHE_HOST:=cache-eu-central-staging.tuist.dev}"
: "${REGION:=eu-central}"
SERVER_URL="${SERVER_URL:-https://staging.tuist.dev}"

cd "${MISE_PROJECT_ROOT}/k6"

k6_args=(
  run src/main.ts
  -e "CACHE_HOST=${CACHE_HOST}"
  -e "CACHE_AUTH_TOKEN=${CACHE_AUTH_TOKEN}"
  -e "SERVER_URL=${SERVER_URL}"
  -e "REGION=${REGION}"
)

if [ -n "${RUN_ID:-}" ]; then
  k6_args+=(-e "RUN_ID=${RUN_ID}")
fi

if [ -n "${COMMIT_SHA:-}" ]; then
  k6_args+=(-e "COMMIT_SHA=${COMMIT_SHA}")
fi

k6 "${k6_args[@]}"
