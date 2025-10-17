#!/usr/bin/env bash
#MISE description="Run CAS worker tests"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WORKER_DIR="$REPO_ROOT/cas-worker"

pnpm --dir "$WORKER_DIR" exec vitest run "$@"
