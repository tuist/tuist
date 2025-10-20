#!/usr/bin/env bash
#MISE description="Deploy the CAS worker"

set -euo pipefail

pnpm --dir "$MISE_PROJECT_ROOT" exec wrangler deploy "$@"
