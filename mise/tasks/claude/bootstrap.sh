#!/usr/bin/env bash
#MISE description="Bootstrap this worktree for Claude Code (launch.json + server install)"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKTREE_ROOT="$(git rev-parse --show-toplevel)"

"${SCRIPT_DIR}/regenerate-launch-json.sh"

# Delegates to server's mise install, which installs deps and bootstraps
# the per-worktree PG + CH databases when missing.
(cd "${WORKTREE_ROOT}/server" && mise run install)
