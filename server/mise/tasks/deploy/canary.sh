#!/usr/bin/env bash
#MISE description="Deploys the app to canary"

set -euo pipefail

flyctl deploy -c fly.canary.toml --dockerfile Dockerfile --build-arg TUIST_HOSTED=1 --build-arg MIX_ENV=can --vm-memory=2048 --wait-timeout 600
