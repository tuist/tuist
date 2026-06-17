#!/usr/bin/env bash
# Runs the Kura gRPC upload-throughput e2e test and exits with the client's
# code (0 = patched beat baseline by >= MIN_SPEEDUP, non-zero = regression).
#
# Tunables (env):
#   SIZE_MB     payload uploaded per path        (default 16)
#   LATENCY_MS  one-way latency; RTT ~= 2x        (default 50)
#   CHUNK_KB    ByteStream chunk size             (default 256)
#   MIN_SPEEDUP required patched/baseline ratio   (default 4)
#   KURA_IMAGE  kura image under test             (default kura:e2e, built from source if absent)
set -euo pipefail

cd "$(dirname "$0")"

cleanup() { docker compose down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

cleanup

# Build the measurement client image (also used by the confgen step below). kura
# is built lazily by `up` from source if its image (KURA_IMAGE, default kura:e2e)
# isn't present locally; in CI the image is prebuilt and retagged, so no kura
# rebuild happens here.
docker compose build client

# Render baseline/patched nginx confs + window.env from the live chart values,
# using the client image's `genconfs` subcommand (no third-party yq image). The
# confgen service is profile-gated so it never joins the `up` lifecycle.
mkdir -p generated
docker compose --profile confgen run --rm confgen

# Export the chart-derived patched window so the client's reference ceiling
# reflects helm too (compose interpolates these into the client env).
if [ -f generated/window.env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./generated/window.env
  set +a
fi

# --exit-code-from propagates the client's exit code and stops the stack when it ends.
docker compose up --abort-on-container-exit --exit-code-from client
