#!/usr/bin/env bash
#MISE description="Run CAS worker tests"

set -euo pipefail

pnpm --dir "$MISE_PROJECT_ROOT" exec vitest run "$@"
