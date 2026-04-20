#!/bin/bash
#MISE description="Install all necessary dependencies"

set -euo pipefail

postgres_database_exists() {
  psql -Atqc "SELECT 1 FROM pg_database WHERE datname = '${TUIST_SERVER_POSTGRES_DB}'" postgres | grep -qx 1
}

clickhouse_database_exists() {
  curl -fsS http://localhost:8123 --data-binary "EXISTS DATABASE ${TUIST_SERVER_CLICKHOUSE_DB}" | grep -qx 1
}

mix deps.get
pnpm install --ignore-workspace
pushd .. >/dev/null
pnpm install --filter noora
popd >/dev/null
pushd ../noora >/dev/null
pnpm run build
popd >/dev/null

if [ -z "${CI:-}" ]; then
  # Fresh worktrees use isolated database names and need the schema dump loaded before later migrations run.
  if ! postgres_database_exists || ! clickhouse_database_exists; then
    mise run db:create
    mise run db:load
  fi

  mise run db:migrate
  mise run db:seed
fi
