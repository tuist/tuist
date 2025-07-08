#!/usr/bin/env bash
# mise description="Deploys the app to canary"

set -euo pipefail

(cd server && flyctl deploy -c fly.canary.toml --dockerfile Dockerfile --build-arg TUIST_HOSTED=1 --build-arg MIX_ENV=can --vm-memory=2048 --wait-timeout 600)
