#!/usr/bin/env bash
# mise description="Deploys the app to production"

set -euo pipefail

flyctl deploy -c fly.prod.toml --dockerfile Dockerfile --build-arg TUIST_HOSTED=1 --build-arg MIX_ENV=prod --vm-memory=2048 --wait-timeout 600
