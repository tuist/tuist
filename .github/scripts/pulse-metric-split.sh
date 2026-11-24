#!/usr/bin/env bash
# Splits Pulse's metric table (public.pulse_physical_table) into partitions by
# instance, as planned in the metric-table split plan. Runs against the cluster
# in the current kubectl context, through the same probe pod as the datanode
# rollout, so the pilot login never reaches the runner.
#
#   pulse-metric-split.sh measure   rows per planned range over the last 10 minutes
#   pulse-metric-split.sh split     run the split, timing reads while it runs
#   pulse-metric-split.sh rewrite   rewrite pre-split files, one day per call
#   pulse-metric-split.sh status    partitions, regions and their placement
#
# DEPLOY_ENV must be listed in the chart's cluster.gc.environments: a split
# needs GC, and after one metasrv refuses to start with GC off.
set -euo pipefail

mode=${1:?usage: pulse-metric-split.sh measure|split|rewrite|status}
: "${DEPLOY_ENV:?DEPLOY_ENV must name the environment}"
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=.github/scripts/pulse-probe.sh
source "$(dirname "${BASH_SOURCE[0]}")/pulse-probe.sh"

table=pulse_physical_table
# Nine ranges, three per datanode, cut at production's row quantiles on
# 2026-11-17 (10-13% each). Rows with no instance go to the first. Pod IPs,
# Kura (one instance per customer and region) and fleet nodes each get several
# ranges, so growth in any one spreads over regions the deploy's rebalance can
# place apart; a range has to roughly triple relative to the rest before it
# fills a datanode, which the rebalance step warns about.
bounds=('192.168.3' '192.168.61' '192.168.98' 'kura/kura-b' 'kura/kura-k' 'kura/kura-r'
  'tuist-md-0' 'tuist-tuist-ovh-fleet-s')

if ! yq -e ".cluster.gc.environments | contains([\"$DEPLOY_ENV\"])" \
  "$repo_root/infra/helm/pulse/values.yaml" > /dev/null 2>&1; then
  echo "::error::$DEPLOY_ENV does not run GC (cluster.gc.environments); a split needs it."
  exit 1
fi

partition_list() {
  local previous="" bound
  for bound in "${bounds[@]}"; do
    if [[ -z $previous ]]; then
      printf "instance < '%s',\n" "$bound"
    else
      printf "instance >= '%s' AND instance < '%s',\n" "$previous" "$bound"
    fi
    previous=$bound
  done
  printf "instance >= '%s'" "$previous"
}

status() {
  echo "Partitions:"
  sql "SELECT partition_name, partition_expression FROM information_schema.partitions
       WHERE table_schema = 'public' AND table_name = '$table' ORDER BY partition_ordinal_position"
  echo "Physical regions (rows, disk bytes, leader):"
  sql "SELECT s.region_id, s.region_rows, s.disk_size, p.peer_addr
       FROM information_schema.region_statistics s
       JOIN information_schema.region_peers p ON s.region_id = p.region_id AND p.is_leader = 'Yes'
       WHERE s.table_id = (SELECT table_id FROM information_schema.tables
                           WHERE table_schema = 'public' AND table_name = '$table')
       ORDER BY s.region_id"
  echo "Leader regions per datanode (logical tables included):"
  sql "SELECT peer_addr, count(*) FROM information_schema.region_peers
       WHERE is_leader = 'Yes' GROUP BY peer_addr ORDER BY peer_addr"
}

measure() {
  local ranges
  ranges=$(printf '%s\n' "${bounds[@]}" | jq -R . | jq -sc .)
  # Ten minutes: an hour of production's metric region exceeds the timeout.
  sql "SELECT instance, count(*) FROM $table
       WHERE pulse_timestamp > now() - INTERVAL '10 minutes' GROUP BY instance" |
    jq -rs --argjson b "$ranges" '
      def range: .[0] as $i | if $i == null then 0
        else ([$b[] | select(. <= $i)] | length) end;
      (map(.[1]) | add) as $total
      | group_by(range)
      | map({range: (.[0] | range), instances: length, rows: (map(.[1]) | add)})
      | .[] | "range \(.range): \(.rows) rows (\(.rows * 100 / $total | floor)%), \(.instances) instances"'
}

# One read of the freshest sample on a logical table; prints "ok <lag ms>" or
# "error". Timed out or failed reads are what the split must not cause.
read_probe() {
  local now newest
  now=$(date +%s%3N)
  if newest=$(PULSE_SQL_TIMEOUT_SECONDS=5 sql "SELECT max(pulse_timestamp) FROM up
       WHERE pulse_timestamp > now() - INTERVAL '10 minutes'" 2> /dev/null | jq -r '.[0]') &&
    [[ $newest =~ ^[0-9]+$ ]]; then
    echo "ok $((now - newest))"
  else
    echo "error"
  fi
}

split() {
  local regions
  regions=$(sql "SELECT count(*) FROM information_schema.partitions
                 WHERE table_schema = 'public' AND table_name = '$table'" | jq -r '.[0]')
  if [[ $regions != 1 ]]; then
    echo "::error::$table already has $regions partitions."
    exit 1
  fi
  status

  local ddl log started finished
  ddl="ALTER TABLE $table PARTITION ON COLUMNS (instance) (
$(partition_list)
) WITH (TIMEOUT = '10m', WAIT = true)"
  echo "$ddl"
  log=$(mktemp)
  started=$(date +%s)
  PULSE_SQL_TIMEOUT_SECONDS=900 sql "$ddl" > "$log" 2>&1 &
  local ddl_pid=$!

  # Reads every second while the split runs and for two minutes after, so a
  # write stall shows as growing lag and a read failure as an error.
  local samples=() result
  while kill -0 "$ddl_pid" 2> /dev/null; do
    result=$(read_probe)
    samples+=("$(($(date +%s) - started)) $result")
    sleep 1
  done
  local ddl_status=0
  wait "$ddl_pid" || ddl_status=$?
  finished=$(date +%s)
  echo "Split statement returned $ddl_status after $((finished - started)) s:"
  cat "$log"
  while (($(date +%s) - finished < 120)); do
    result=$(read_probe)
    samples+=("$(($(date +%s) - started)) $result")
    sleep 1
  done

  printf '%s\n' "${samples[@]}" | awk -v split_end=$((finished - started)) '
    { n++ }
    $2 == "error" { errors++; if ($1 <= split_end) during++; print "read failed at +" $1 "s"; next }
    { lag = $3 / 1000; if (lag > max) { max = lag; at = $1 } }
    END {
      printf "Reads: %d, failed: %d (%d during the split). Highest freshness lag: %.0f s at +%d s.\n",
        n, errors, during, max, at
    }'
  sleep 1
  status
  return "$ddl_status"
}

# Rewrites one UTC day of history with strict-window compaction, which writes
# files owned by each region instead of the shared pre-split ones.
# PULSE_REWRITE_DAY is one UTC day (2026-11-10) or an inclusive range
# (2026-11-10..2026-11-16), rewritten one day per statement.
rewrite() {
  local range=${PULSE_REWRITE_DAY:?PULSE_REWRITE_DAY must be a UTC day such as 2026-11-10}
  local day=${range%%..*} last=${range##*..} next started
  [[ "$(date -u -d "$day" +%F)" == "$day" && "$(date -u -d "$last" +%F)" == "$last" && ! "$last" < "$day" ]] || {
    echo "::error::PULSE_REWRITE_DAY must be YYYY-MM-DD or YYYY-MM-DD..YYYY-MM-DD, earliest first." >&2
    exit 2
  }
  while [[ ! "$day" > "$last" ]]; do
    next=$(date -u -d "$day + 1 day" +%F)
    started=$(date +%s)
    PULSE_SQL_TIMEOUT_SECONDS=3600 sql "ADMIN compact_table('$table', 'swcs',
      'window=86400,start_time=${day}T00:00:00Z,end_time=${next}T00:00:00Z')"
    echo "Rewrote $day in $(($(date +%s) - started)) s."
    day=$next
  done
  status
}

start_probe
case $mode in
  measure) measure ;;
  split) split ;;
  rewrite) rewrite ;;
  status) status ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
