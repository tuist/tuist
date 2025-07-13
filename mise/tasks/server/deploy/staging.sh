#!/usr/bin/env bash
# mise description="Deploys the app to staging"

set -euo pipefail

(cd server && flyctl deploy -c fly.staging.toml --dockerfile Dockerfile --build-arg TUIST_HOSTED=1 --build-arg MIX_ENV=stag --vm-memory=2048 --wait-timeout 600)
