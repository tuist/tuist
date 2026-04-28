#!/bin/bash
#MISE description="Install all necessary dependencies"

set -euo pipefail

CLICKHOUSE_HTTP_URL="${TUIST_SERVER_CLICKHOUSE_HTTP_URL:-http://127.0.0.1:${TUIST_SERVER_CLICKHOUSE_HTTP_PORT:-8123}}"

postgres_database_exists() {
  psql -Atqc "SELECT 1 FROM pg_database WHERE datname = '${TUIST_SERVER_POSTGRES_DB}'" postgres | grep -qx 1
}

postgres_database_bootstrapped() {
  psql -d "${TUIST_SERVER_POSTGRES_DB}" -Atqc \
    "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users')" |
    grep -qx t
}

clickhouse_database_exists() {
  curl -fsS "${CLICKHOUSE_HTTP_URL}" --data-binary "EXISTS DATABASE ${TUIST_SERVER_CLICKHOUSE_DB}" | grep -qx 1
}

bootstrap_postgres_database() {
  mix ecto.create -r Tuist.Repo
  mix ecto.load -r Tuist.Repo
}

rebootstrap_postgres_database() {
  mix ecto.drop -r Tuist.Repo
  bootstrap_postgres_database
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
  # Fresh worktrees use isolated database names, so bootstrap missing repos independently.
  if ! postgres_database_exists; then
    bootstrap_postgres_database
  elif ! postgres_database_bootstrapped; then
    # A previous install may have created the DB but exited before `ecto.load`
    # finished. In that state later runs skip bootstrapping and migrations fail
    # against missing base tables such as `users`, so rebuild the local DB.
    rebootstrap_postgres_database
  fi

  if ! clickhouse_database_exists; then
    bootstrap_clickhouse_database
  fi

  mise run db:migrate
  mise run db:seed
fi
