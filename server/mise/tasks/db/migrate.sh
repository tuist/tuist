#!/usr/bin/env bash
#MISE description="Migrates the database"

set -euo pipefail

mix ecto.migrate

# A migration that takes the VM down (rather than raising) can leave `mix
# ecto.migrate` exiting 0 with migrations still pending, which silently hands a
# half-migrated database to the seeds. Fail loudly instead.
migration_status="$(mix ecto.migrations)"
pending="$(printf '%s\n' "${migration_status}" | grep -E '^\s+down\s+[0-9]+' || true)"

if [ -n "${pending}" ]; then
  echo "Migrations are still pending after 'mix ecto.migrate':" >&2
  echo "${pending}" >&2
  exit 1
fi
