#!/bin/bash

set -euo pipefail

LOG=/var/log/tuist-runner/kura.log
exec >>"${LOG}" 2>&1

timestamp() {
  date -u +%FT%TZ
}

ready_file="${TUIST_RUNNER_LOCAL_CACHE_READY_FILE:-}"
cache_dir="${TUIST_RUNNER_LOCAL_CACHE_DIR:-}"
endpoint="${TUIST_RUNNER_LOCAL_KURA_ENDPOINT:-http://127.0.0.1:4000}"
peer_url="${1:-}"
wait_seconds="${TUIST_RUNNER_LOCAL_CACHE_READY_TIMEOUT_SECONDS:-120}"
startup_seconds="${TUIST_RUNNER_LOCAL_KURA_STARTUP_TIMEOUT_SECONDS:-60}"

if [ -z "${ready_file}" ] || [ -z "${cache_dir}" ]; then
  echo "$(timestamp) local-kura: local cache env missing; skipping"
  exit 1
fi

if [ ! -x /usr/local/bin/kura ]; then
  echo "$(timestamp) local-kura: /usr/local/bin/kura missing; skipping"
  exit 1
fi

if curl -fsS "${endpoint}/ready" >/dev/null 2>&1; then
  echo "$(timestamp) local-kura: already ready at ${endpoint}"
  exit 0
fi

elapsed=0
while [ ! -f "${ready_file}" ] && [ "${elapsed}" -lt "${wait_seconds}" ]; do
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ ! -f "${ready_file}" ]; then
  echo "$(timestamp) local-kura: cache ready marker ${ready_file} missing after ${wait_seconds}s"
  exit 1
fi

account_id="$(head -n 1 "${ready_file}" | tr -d '[:space:]')"
if [ -z "${account_id}" ]; then
  echo "$(timestamp) local-kura: cache ready marker ${ready_file} is empty"
  exit 1
fi

if [[ "${peer_url}" == https://* ]]; then
  echo "$(timestamp) local-kura: mTLS peer URL provided but runner-local peer credentials are not installed; starting without peers"
  peer_url=""
fi

mkdir -p "${cache_dir}/tmp"

export KURA_PORT="${KURA_PORT:-4000}"
export KURA_GRPC_PORT="${KURA_GRPC_PORT:-50051}"
export KURA_INTERNAL_PORT="${KURA_INTERNAL_PORT:-7443}"
export KURA_TENANT_ID="${account_id}"
export KURA_REGION="${KURA_REGION:-runner-local}"
export KURA_DATA_DIR="${cache_dir}"
export KURA_TMP_DIR="${cache_dir}/tmp"
export KURA_NODE_URL="${KURA_NODE_URL:-http://127.0.0.1:${KURA_INTERNAL_PORT}}"
export KURA_PEERS="${peer_url}"
export KURA_BOOTSTRAP_ENABLED="${KURA_BOOTSTRAP_ENABLED:-false}"
export KURA_ACCELERATED_FILE_SERVING_ENABLED="${KURA_ACCELERATED_FILE_SERVING_ENABLED:-false}"
export KURA_OTEL_SERVICE_NAME="${KURA_OTEL_SERVICE_NAME:-tuist-runner-local-kura}"
export KURA_OTEL_DEPLOYMENT_ENVIRONMENT="${KURA_OTEL_DEPLOYMENT_ENVIRONMENT:-runner-local}"

echo "$(timestamp) local-kura: starting Kura for account ${account_id} at ${endpoint}"
/usr/local/bin/kura &
echo "$!" > "${cache_dir}/.tuist-local-kura.pid"

elapsed=0
while [ "${elapsed}" -lt "${startup_seconds}" ]; do
  if curl -fsS "${endpoint}/ready" >/dev/null 2>&1; then
    echo "$(timestamp) local-kura: ready at ${endpoint}"
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

echo "$(timestamp) local-kura: did not become ready after ${startup_seconds}s"
exit 1
