#!/usr/bin/env bash
#MISE description="Seed the dev databases for this worktree (idempotent, marker-guarded)"

set -euo pipefail

WORKTREE_ROOT="$(git rev-parse --show-toplevel)"
MARKER_FILE="${WORKTREE_ROOT}/.tuist-dev-seeded"

if [[ -f "${MARKER_FILE}" ]]; then
  exit 0
fi

echo "worktree:seed-db: seeding databases for this worktree (one-time)..."

# Fresh-DB flow: create → load structure dump → migrate post-dump migrations → seed.
# `mix ecto.setup` skips ecto.load, which is required because early schema is in structure.sql.
if ! (
  cd "${WORKTREE_ROOT}/server" && \
  mise run db:create && \
  mise run db:load && \
  mise run db:migrate && \
  mise run db:seed
); then
  echo "worktree:seed-db: seeding failed — ensure PostgreSQL and ClickHouse are running, then re-run 'mise run worktree:seed-db'." >&2
  exit 1
fi

touch "${MARKER_FILE}"
echo "worktree:seed-db: done."
