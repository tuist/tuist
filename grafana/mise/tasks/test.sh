#!/usr/bin/env bash
#MISE description="Test the Tuist Grafana app plugin"
set -euo pipefail
pnpm run typecheck
pnpm run test:ci
