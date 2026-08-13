#!/usr/bin/env bash
#MISE description="Drop dev databases left behind by worktrees that no longer exist"

set -euo pipefail

# Every worktree gets a numeric suffix (mise/utilities/dev_instance_env.sh) and
# its own `tuist_development_<suffix>`, `tuist_test<partition>_<suffix>` and
# `cache_test_<suffix>` databases. Removing a worktree leaves those behind with
# nothing to reap them. ClickHouse pays a per-table background cost whether or
# not a table is ever queried, so the leftovers are not merely wasted disk: at
# ~100 tables per instance they accumulate into thousands of idle tables, and
# the scheduler burns CPU ticking all of them forever.

MIN_LIVE_SUFFIXES=3
DRY_RUN=0

for arg in "$@"; do
  case "${arg}" in
  --dry-run) DRY_RUN=1 ;;
  *)
    echo "Unknown argument: ${arg}" >&2
    echo "Usage: ${0##*/} [--dry-run]" >&2
    exit 2
    ;;
  esac
done

PROJECT_ROOT="${MISE_PROJECT_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
CLICKHOUSE_HTTP_URL="${TUIST_SERVER_CLICKHOUSE_HTTP_URL:-http://127.0.0.1:${TUIST_SERVER_CLICKHOUSE_HTTP_PORT:-8123}}"

common_dir="$(git -C "${PROJECT_ROOT}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [[ -z "${common_dir}" || ! -d "${common_dir}" ]]; then
  echo "prune-dev-instances: not a git checkout; nothing to do"
  exit 0
fi

# The suffixes still claimed by the main checkout or a linked worktree. A
# database is only ever created after its instance file is persisted, so a live
# instance can never be missing from this set.
live="$(
  for f in "${common_dir}/tuist-dev-instance" "${common_dir}"/worktrees/*/tuist-dev-instance; do
    [[ -s "${f}" ]] || continue
    tr -d '[:space:]' <"${f}"
    printf '\n'
  done | grep -E '^[0-9]+$' | sort -u || true
)"

live_count="$(printf '%s\n' "${live}" | grep -c . || true)"

# An empty or implausibly small live set means the worktree metadata could not
# be read, not that every worktree was deleted. Pruning on that reading would
# drop every dev database on the machine, so refuse instead.
if ((live_count < MIN_LIVE_SUFFIXES)); then
  echo "prune-dev-instances: found only ${live_count} live dev instance(s), expected at least ${MIN_LIVE_SUFFIXES}." >&2
  echo "prune-dev-instances: refusing to prune; ${common_dir} may be unreadable." >&2
  exit 0
fi

# Databases whose trailing _<digits> suffix belongs to no live worktree.
# The suffix list is passed space-separated: BSD awk rejects a -v value
# containing newlines.
select_orphans() {
  awk -v live="$(printf '%s' "${live}" | tr '\n' ' ')" -v pat="$1" '
    BEGIN {
      n = split(live, entries, " ")
      for (i = 1; i <= n; i++) if (entries[i] != "") alive[entries[i]] = 1
    }
    $0 ~ pat {
      suffix = $0
      sub(/^.*_/, "", suffix)
      if (!(suffix in alive)) print
    }
  '
}

clickhouse_query() {
  curl -fsS "${CLICKHOUSE_HTTP_URL}" --data-binary "$1"
}

dropped=0
skipped=0

if databases="$(clickhouse_query "SELECT name FROM system.databases" 2>/dev/null)"; then
  while read -r database; do
    [[ -n "${database}" ]] || continue
    if ((DRY_RUN)); then
      echo "would drop clickhouse ${database}"
      continue
    fi
    # SYNC matters: without it the Atomic engine defers the delete by
    # `database_atomic_delay_before_drop_table_sec` (480s by default) and the
    # background cost stays until then.
    if clickhouse_query "DROP DATABASE IF EXISTS \`${database}\` SYNC" >/dev/null 2>&1; then
      dropped=$((dropped + 1))
    else
      echo "prune-dev-instances: failed to drop clickhouse ${database}" >&2
    fi
  done < <(printf '%s\n' "${databases}" | select_orphans '^(tuist_development|tuist_test[0-9]*)_[0-9]+$')
else
  skipped=$((skipped + 1))
  echo "prune-dev-instances: ClickHouse unreachable at ${CLICKHOUSE_HTTP_URL}; skipping"
fi

if psql -Atqc 'SELECT 1' postgres >/dev/null 2>&1; then
  while read -r database; do
    [[ -n "${database}" ]] || continue
    if ((DRY_RUN)); then
      echo "would drop postgres ${database}"
      continue
    fi
    # FORCE terminates connections a dead worktree's pool may still hold.
    if psql -Atqc "DROP DATABASE IF EXISTS \"${database}\" WITH (FORCE)" postgres >/dev/null 2>&1; then
      dropped=$((dropped + 1))
    else
      echo "prune-dev-instances: failed to drop postgres ${database}" >&2
    fi
  done < <(psql -Atqc "SELECT datname FROM pg_database" postgres | select_orphans '^(tuist_development|tuist_test[0-9]*|cache_test)_[0-9]+$')
else
  skipped=$((skipped + 1))
  echo "prune-dev-instances: Postgres unreachable; skipping"
fi

if ((DRY_RUN)); then
  exit 0
fi

if ((dropped > 0)); then
  echo "prune-dev-instances: dropped ${dropped} database(s) from removed worktrees"
fi
