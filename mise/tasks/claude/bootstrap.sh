#!/usr/bin/env bash
#MISE description="Bootstrap this worktree for Claude Code (launch.json + DB seed)"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/regenerate-launch-json.sh"
"${SCRIPT_DIR}/seed-db.sh"
