#!/usr/bin/env bash
# Decides whether a Server run tests against the oldest supported ClickHouse.
#
# Usage:
#   server-clickhouse-floor.sh <event-name> [<repository> <pull-request-number>]
#   server-clickhouse-floor.sh --files <pull-request-files.json>
#
# Prints `true` or `false` on stdout and the reason on stderr. Pull requests
# run the floor shards when they carry the `ci:clickhouse-floor` label, change
# ClickHouse migrations, configuration, versions or the workflow, or add lines
# under server/lib or server/priv that look like ClickHouse queries. Every other
# event always runs them. Anything that cannot be read runs them.

set -euo pipefail

LABEL="ci:clickhouse-floor"

PATH_PATTERN='^(server/priv/ingest_repo/|server/lib/tuist/clickhouse|server/lib/tuist/ingest_repo|server/config/|server/mix\.lock$|mise\.lock$|\.github/workflows/server\.yml$|\.github/scripts/server-clickhouse-floor)'
SOURCE_PATTERN='^server/(lib|priv)/.*\.exs?$'
QUERY_PATTERN='ClickHouseRepo|IngestRepo|fragment\(|(^|[^A-Za-z_])FINAL([^A-Za-z_]|$)|SETTINGS|settings: \[|argMax|quantile|toStartOf|arrayJoin|groupArray|uniqExact|LowCardinality|AggregateFunction|MergeTree|Ch, type:'

run() {
  echo "true"
  echo "Running the oldest supported ClickHouse shards: $1" >&2
  exit 0
}

skip() {
  echo "false"
  echo "Skipping the oldest supported ClickHouse shards: $1" >&2
  exit 0
}

# Reads the pull request files API response (an array of objects with
# filename, previous_filename and patch) and decides from it alone.
decide_from_files() {
  local files="$1" name patch

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if printf '%s\n' "$name" | grep -Eq "$PATH_PATTERN"; then
      run "$name changed"
    fi
  done < <(jq -r '.[] | .filename, (.previous_filename // empty)' "$files")

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! printf '%s\n' "$name" | grep -Eq "$SOURCE_PATTERN"; then
      continue
    fi
    if [ "$(jq --arg name "$name" '[.[] | select(.filename == $name) | has("patch")] | all' "$files")" != "true" ]; then
      run "GitHub returned no patch for $name"
    fi
    patch="$(jq -r --arg name "$name" '.[] | select(.filename == $name) | .patch' "$files")"
    if printf '%s\n' "$patch" | grep -E '^\+' | grep -Ev '^\+\+\+' | grep -Eq "$QUERY_PATTERN"; then
      run "$name adds ClickHouse query code"
    fi
  done < <(jq -r '.[].filename' "$files")

  skip "no ClickHouse migrations, configuration or queries changed"
}

if [ "${1:-}" = "--files" ]; then
  decide_from_files "$2"
fi

event="${1:?event name required}"
if [ "$event" != "pull_request" ]; then
  run "$event runs always test it"
fi

repository="${2:?repository required}"
number="${3:?pull request number required}"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

if ! gh api "repos/$repository/issues/$number/labels" --paginate --jq '.[].name' > "$scratch/labels"; then
  run "the pull request's labels could not be read"
fi
if grep -qxF "$LABEL" "$scratch/labels"; then
  run "the pull request has the $LABEL label"
fi

if ! gh api "repos/$repository/pulls/$number/files?per_page=100" --paginate --slurp > "$scratch/pages"; then
  run "the pull request's files could not be read"
fi
jq 'add // []' "$scratch/pages" > "$scratch/files"
decide_from_files "$scratch/files"
