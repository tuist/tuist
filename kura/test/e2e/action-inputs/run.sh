#!/usr/bin/env bash
# Runs the Kura action-inputs e2e test and exits with the client's code.
#   KURA_IMAGE  kura image under test (default kura:e2e, built from source unless
#               KURA_E2E_SKIP_BUILD=1)
set -euo pipefail

cd "$(dirname "$0")"

cleanup() { docker compose down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

cleanup
docker compose build client
if [ -z "${KURA_IMAGE:-}" ] && [ "${KURA_E2E_SKIP_BUILD:-0}" != "1" ]; then
  docker compose build kura
fi
docker compose up --abort-on-container-exit --exit-code-from client
