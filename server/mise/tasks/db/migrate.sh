#!/usr/bin/env bash
#MISE description="Migrates the database"

set -euo pipefail

# `--create` creates the databases first, in the same Mix process.
tasks=(ecto.migrate)
if [ "${1:-}" = "--create" ]; then
  tasks=(ecto.create + ecto.migrate)
fi

# A migration that takes the VM down (rather than raising) can leave Mix
# exiting 0 with migrations still pending, which silently hands a
# half-migrated database to the seeds. List the migrations in the same
# process and fail loudly unless that listing ran and shows nothing pending.
output="$(mktemp)"
trap 'rm -f "${output}"' EXIT

mix 'do' "${tasks[@]}" + ecto.migrations | tee "${output}" | sed '/^Repo: /,$d'

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
