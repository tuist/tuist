#!/usr/bin/env bash
#MISE description="Bootstrap this worktree (seed DBs, write launch.json)"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/seed-db.sh"
"${SCRIPT_DIR}/launch-json.sh"
