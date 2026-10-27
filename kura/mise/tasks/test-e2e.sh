#!/usr/bin/env bash
#MISE description="Run the end-to-end shellspec suite against the Dockerized service (pass shellspec args through, e.g. mise run test-e2e -- -j 8)"
set -euo pipefail

# Build the kura image once and share it across every suite. The compose services
# declare `image: ${KURA_IMAGE:-}` (empty by default, so local `docker compose up`
# keeps its per-project image naming), so exporting a fixed KURA_IMAGE makes every
# suite -- regardless of its COMPOSE_PROJECT_NAME -- resolve to this one prebuilt
# image. No per-project rebuilds, which is what would otherwise serialize parallel
# `-j` workers. The suites then run with KURA_E2E_SKIP_BUILD=1 and reuse it.
export KURA_IMAGE=kura:e2e
docker compose build

KURA_E2E_SKIP_BUILD=1 shellspec "$@"
