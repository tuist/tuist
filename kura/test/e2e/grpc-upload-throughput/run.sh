#!/usr/bin/env bash
# Runs the Kura gRPC upload-throughput e2e test and exits with the client's
# code (0 = patched beat baseline by >= MIN_SPEEDUP, non-zero = regression).
#
# Tunables (env):
#   SIZE_MB     payload uploaded per path        (default 24)
#   LATENCY_MS  one-way latency; RTT ~= 2x        (default 50)
#   CHUNK_KB    ByteStream chunk size             (default 256)
#   MIN_SPEEDUP required patched/baseline ratio   (default 4)
#   KURA_IMAGE  kura image under test             (default ghcr.io/tuist/kura:0.10.1)
set -euo pipefail

cd "$(dirname "$0")"

cleanup() { docker compose down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

cleanup
docker compose build
# --exit-code-from propagates the client's exit code and stops the stack when it ends.
docker compose up --abort-on-container-exit --exit-code-from client
