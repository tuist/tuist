#!/usr/bin/env bash
#MISE description="Bootstrap the dev databases for this worktree (idempotent, marker-guarded)"

set -euo pipefail

WORKTREE_ROOT="$(git rev-parse --show-toplevel)"
MARKER_FILE="${WORKTREE_ROOT}/.tuist-dev-seeded"

if [[ -f "${MARKER_FILE}" ]]; then
  exit 0
fi

echo "claude:seed-db: bootstrapping databases for this worktree (one-time)..."

# Delegates to server's mise install, which handles:
#   - ensure PG/CH databases exist (create + load schema dumps if missing)
#   - mix deps.get, pnpm install, Noora build
#   - db:migrate + db:seed
# Marker-guarded so SessionStart re-runs don't re-seed (seeds.exs is not idempotent).
if ! (cd "${WORKTREE_ROOT}/server" && mise run install); then
  echo "claude:seed-db: mise install failed — ensure PostgreSQL and ClickHouse are running, then re-run 'mise run claude:seed-db'." >&2
  exit 1
fi

touch "${MARKER_FILE}"
echo "claude:seed-db: done."
