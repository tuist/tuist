#!/usr/bin/env bash
#MISE description="Fails when two migrations in the same repo share a version"

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SERVER_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)

status=0

for migrations_dir in priv/repo/migrations priv/ingest_repo/migrations; do
  path="$SERVER_DIR/$migrations_dir"
  [ -d "$path" ] || continue

  duplicates=$(
    find "$path" -maxdepth 1 -name '*.exs' -exec basename {} \; |
      sed -E 's/^([0-9]+)_.*/\1/' |
      sort |
      uniq -d
  )

  [ -n "$duplicates" ] || continue

  status=1

  while IFS= read -r version; do
    echo "Duplicate migration version $version in $migrations_dir:"
    find "$path" -maxdepth 1 -name "${version}_*.exs" -exec basename {} \; |
      sort |
      sed 's/^/  /'
  done <<<"$duplicates"
done

if [ "$status" -ne 0 ]; then
  cat <<'MESSAGE'

Ecto identifies an applied migration by its version alone. Two files sharing a
version abort the entire run on a database that has applied neither, and leave
the second one silently unapplied on a database that already recorded the first.

Renumber whichever migration has not been deployed anywhere yet, and leave the
one already recorded in a deployed environment at its original version.
MESSAGE
fi

exit "$status"
