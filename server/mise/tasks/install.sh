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
  # The project's ecto.create alias starts the application. Call Ecto directly
  # while bootstrapping, before all databases exist (as db:migrate --create does).
  mix run --no-start -e 'Mix.Tasks.Ecto.Create.run(["-r", "Tuist.Repo"])'
  mix ecto.migrate -r Tuist.Repo
}

rebootstrap_postgres_database() {
  mix ecto.drop -r Tuist.Repo
  bootstrap_postgres_database
}

bootstrap_clickhouse_database() {
  mix run --no-start -e 'Mix.Tasks.Ecto.Create.run(["-r", "Tuist.IngestRepo"])'
  mix ecto.load -r Tuist.IngestRepo
}

if [ -n "${CI:-}" ]; then
  # CI jobs install only the tools they request and bootstrap deps explicitly in
  # the workflow. Skipping the local postinstall avoids pulling in aube/noora
  # setup on jobs that only need Mix or ClickHouse.
  exit 0
fi

TIMEFORMAT='<== Fetching Mix dependencies: %3Rs'
time mix deps.get
TIMEFORMAT='<== Installing server assets: %3Rs'
time aube install
pushd ../noora >/dev/null
TIMEFORMAT='<== Installing Noora assets: %3Rs'
time aube install
TIMEFORMAT='<== Building Noora assets: %3Rs'
time aube run build
popd >/dev/null

# Compile through the cache-aware alias before discovering database tasks.
# On a cold checkout, discovering db.create first compiles dependencies before
# the alias has a chance to restore them.
TIMEFORMAT='<== Compiling the server dev build: %3Rs'
time mix compile

# Fresh worktrees use isolated database names, so bootstrap missing repos independently.
TIMEFORMAT='<== Bootstrapping databases: %3Rs'
time {
  if ! postgres_database_exists; then
    bootstrap_postgres_database
  elif ! postgres_database_bootstrapped; then
    # A previous install may have created the DB but exited before migrations
    # finished. In that state later runs skip bootstrapping and migrations fail
    # against missing base tables such as `users`, so rebuild the local DB.
    rebootstrap_postgres_database
  fi

  if ! clickhouse_database_exists; then
    bootstrap_clickhouse_database
  fi
}

TIMEFORMAT='<== Migrating dev databases: %3Rs'
time mise run db:migrate

# Amp orb setup seeds separately, only when the database is empty.
if [ "${1:-}" != "--no-seed" ]; then
  mise run db:seed
fi
