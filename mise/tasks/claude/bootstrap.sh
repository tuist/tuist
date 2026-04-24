#!/usr/bin/env bash
#MISE description="Bootstrap this worktree for Claude Code (launch.json + server install)"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/regenerate-launch-json.sh"

# Prime SwiftPM resolution with --replace-scm-with-registry so that any
# background resolve triggered by sourcekit-lsp / IDE indexing does not
# rewrite Package.resolved from registry pins to source-control revisions.
# Runs in the background so it does not block session start.
(cd "${MISE_PROJECT_ROOT}" && swift package resolve --replace-scm-with-registry >/dev/null 2>&1 &)

# Delegates to server's mise install, which installs deps and bootstraps
# the per-worktree PG + CH databases when missing.
(cd "${MISE_PROJECT_ROOT}/server" && mise run install)
