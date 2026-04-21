#!/bin/bash
#MISE description="Install all necessary dependencies"

set -euo pipefail

postgres_database_exists() {
  psql -Atqc "SELECT 1 FROM pg_database WHERE datname = '${TUIST_SERVER_POSTGRES_DB}'" postgres | grep -qx 1
}

clickhouse_database_exists() {
  local clickhouse_url="${TUIST_CLICKHOUSE_URL:-http://localhost:8123}"
  curl -fsS "${clickhouse_url}" --data-binary "EXISTS DATABASE ${TUIST_SERVER_CLICKHOUSE_DB}" | grep -qx 1
}

bootstrap_postgres_database() {
  mix ecto.create -r Tuist.Repo
  mix ecto.load -r Tuist.Repo
}

bootstrap_clickhouse_database() {
  mix ecto.create -r Tuist.IngestRepo
  mix ecto.load -r Tuist.IngestRepo
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
  mise x -- pitchfork start clickhouse >/dev/null

  # Fresh worktrees use isolated database names, so bootstrap missing repos independently.
  if ! postgres_database_exists; then
    bootstrap_postgres_database
  fi

  if ! clickhouse_database_exists; then
    bootstrap_clickhouse_database
  fi

  mise run db:migrate
  mise run db:seed
fi
