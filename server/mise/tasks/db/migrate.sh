#!/usr/bin/env bash
#MISE description="Migrates the database"

set -euo pipefail

calls="Mix.Tasks.Ecto.Migrate.run([]); Mix.Tasks.Ecto.Migrations.run([])"

# `--create` creates the databases first, in the same Mix process. It calls
# Ecto's task directly: the project's ecto.create alias also starts the app,
# which slows down the migrations that follow.
if [ "${1:-}" = "--create" ]; then
  calls="Mix.Tasks.Ecto.Create.run([]); ${calls}"
fi

# A migration that takes the VM down (rather than raising) can leave Mix
# exiting 0 with migrations still pending, which silently hands a
# half-migrated database to the seeds. List the migrations in the same
# process and fail loudly unless that listing ran and shows nothing pending.
output="$(mktemp)"
trap 'rm -f "${output}"' EXIT

mix run --no-start -e "${calls}" | tee "${output}" | awk '/^Repo: /{listing=1} !listing {print; fflush()}'

if ! grep -E '^\s+Status\s+Migration ID' "${output}" > /dev/null; then
  echo "The migration status was not listed after migrating." >&2
  exit 1
fi

pending="$(grep -E '^\s+down\s+[0-9]+' "${output}" || true)"

if [ -n "${pending}" ]; then
  echo "Migrations are still pending after migrating:" >&2
  echo "${pending}" >&2
  exit 1
fi
