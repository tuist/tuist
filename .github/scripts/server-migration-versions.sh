#!/usr/bin/env bash
# Fail when two server migrations share a version.
#
# Ecto only rejects duplicate versions among pending migrations. A database
# that already recorded the version treats both files as applied and never
# runs the second one, so the deploy must stop before it reaches one.
# Same version rule as server/test/tuist/migration_versions_test.exs, without
# booting Mix.

set -euo pipefail

root="${1:-$(git rev-parse --show-toplevel)}"
status=0

for dir in server/priv/repo/migrations server/priv/ingest_repo/migrations; do
  duplicates="$(find "$root/$dir" -maxdepth 1 -name '*.exs' -exec basename {} \; \
    | sort | awk -F_ '{ files[$1] = files[$1] " " $0; count[$1]++ }
      END { for (v in count) if (count[v] > 1) print v ":" files[v] }')"
  if [ -n "$duplicates" ]; then
    status=1
    while IFS= read -r line; do
      echo "::error::Duplicate migration version ${line%%:*} in $dir:${line#*:}"
    done <<< "$duplicates"
  fi
done

if [ "$status" -ne 0 ]; then
  echo "Rename the migration that has not run anywhere yet to a later, unique version." >&2
fi
exit "$status"
