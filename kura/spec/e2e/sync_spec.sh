# shellcheck shell=bash

# Ring B of docs/replication-test-plan.md: the pull-replication redesign
# (docs/replication-design.md §2–§4, decisions D-1..D-16 in
# docs/replication-implementation.md) on docker compose, one Describe per
# topology. Every node runs on test/e2e/docker-compose.sync.yml with
# KURA_REPLICATION_PULL=true unless the suite says otherwise; membership is
# DNS-only, so each suite starts exactly the nodes its topology names.
#
#   B-1, B-2   two replicas of one region (feed convergence, forward catch-up)
#   B-3        the same pair with a 100-row feed cap (410 → backward pass)
#   B-4        the same pair, drain gate of a departing replica
#   B-5..B-7   two regions × two replicas (gateway links, tombstones, failover)
#   B-8        two regions, pull flipped on in one of them only
#   B-9, B-10  a region of one beside a two-replica region, no server
#   B-11       a pair whose membership is one-way (§11.2's push exception)
#
# Observables are the ones the plan names: /status/cluster (`pulling`,
# `gateway`, `sync_links`, `feed`), /_internal/status (`pulling`,
# `traffic_state`, `peers`), the kura_sync_* / kura_gateway_role* / kura_outbox_messages
# metric families (counters scrape with the doubled `_total_total` suffix;
# metric_sum accepts the registered name), and the nodes' JSON logs where a
# node has already exited. Measured latencies are appended to the file named
# by KURA_E2E_SYNC_MEASUREMENTS when it is set.

SYNC_NAMESPACE=ios
A1_NODE_URL=http://kura-a1.kura.internal:7443
A2_NODE_URL=http://kura-a2.kura.internal:7443
B1_NODE_URL=http://kura-b1.kura.internal:7443
B2_NODE_URL=http://kura-b2.kura.internal:7443
SOLO_NODE_URL=http://kura-solo.kura.internal:7443
D1_NODE_URL=http://kura-d1.kura.internal:7443
D2_NODE_URL=http://kura-d2.kura.internal:7443

# The sync compose file is self-contained (not layered on docker-compose.yml),
# so the project directory is pinned to the crate root for its build context.
sync_compose_files() {
  COMPOSE_FILES=(
    --project-directory "${PROJECT_ROOT}"
    -f "${PROJECT_ROOT}/test/e2e/docker-compose.sync.yml"
  )
}

# Common suite bootstrap: compose files, tmp dir, project name, ephemeral
# ports for every node the file defines (unused ones cost nothing).
sync_setup_project() {
  sync_compose_files
  setup_suite_tmpdir
  suite_env COMPOSE_PROJECT_NAME "$1"
  ephemeral_ports KURA_A1_PORT KURA_A2_PORT KURA_B1_PORT KURA_B2_PORT KURA_SOLO_PORT \
    KURA_D1_PORT KURA_D2_PORT
}

sync_build_nodes() {
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  if [ "${KURA_E2E_SKIP_BUILD:-0}" != "1" ]; then
    dc build "$@" >/dev/null 2>&1 || return 1
  fi
}

# Resolve <SERVICE>_URL for every service given (kura-a1 -> KURA_A1_URL).
# Ephemeral host ports change on every container start, so call it after any
# up/restart and at the start of every example.
resolve_sync_nodes() {
  local service prefix
  for service in "$@"; do
    prefix="$(printf '%s' "$service" | tr '[:lower:]-' '[:upper:]_')"
    resolve_http_node "$prefix" "$service"
  done
}

sync_start_nodes() {
  dc up -d "$@" >/dev/null 2>&1 || return 1
  resolve_sync_nodes "$@"
}

wait_for_node_ready() {
  wait_for_http "$1/up" 60 1 || return 1
  wait_for_status "$1/ready" 200 90 1 >/dev/null || return 1
}

wait_for_ring_members() {
  wait_for_contains "$1/status/cluster" "\"ring_members\":$2" 45 2 >/dev/null
}

# Roles are re-derived once per membership tick from a view that is one
# probe stale, and a node's own `serving` latches after the tick that
# derived its roles (replication/mod.rs: evaluate runs before
# maybe_mark_serving), so for a tick or two after both replicas latch the
# role can sit on the higher URL. Wait for the lowest-URL rule to settle
# before asserting on it.
wait_for_region_roles() {
  local gateway_url="$1"
  shift
  wait_for_output true 60 1 node_gateway "$gateway_url" >/dev/null || return 1
  local url
  for url in "$@"; do
    wait_for_output false 60 1 node_gateway "$url" >/dev/null || return 1
  done
}

# Poll CMD ARGS... until its stdout equals EXPECTED; prints the last output
# either way so the caller can assert on it.
wait_for_output() {
  local expected="$1" attempts="$2" sleep_seconds="$3"
  shift 3
  local output=""
  for _ in $(seq 1 "$attempts"); do
    output="$("$@" 2>/dev/null || true)"
    if [ "$output" = "$expected" ]; then
      printf '%s' "$output"
      return 0
    fi
    sleep "$sleep_seconds"
  done
  printf 'Timed out waiting for [%s] from %s (last: [%s])\n' "$expected" "$*" "$output" >&2
  printf '%s' "$output"
  return 1
}

now_ms() {
  python3 -c 'import time; print(int(time.time() * 1000))'
}

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

record_measurement() {
  printf '%s\n' "$*" >>"${KURA_E2E_SYNC_MEASUREMENTS:-/dev/null}"
}

# --- /status/cluster projections -------------------------------------------

cluster_eval() {
  local url="$1" expression="$2"
  curl -fsS "${url}/status/cluster" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(eval(sys.argv[1]))
' "$expression"
}

node_gateway() { cluster_eval "$1" "str(d['gateway']).lower()"; }
node_pulling() { cluster_eval "$1" "str(d['pulling']).lower()"; }
# One token per link, `kind:region>peer`, sorted; `none` without links.
node_links() {
  cluster_eval "$1" "' '.join(sorted(l['kind'] + ':' + l['region'] + '>' + l['peer'] for l in d['sync_links'])) or 'none'"
}
# true once every link reads forward and has settled (design §3.6).
node_links_settled() {
  cluster_eval "$1" "str(bool(d['sync_links']) and all(l['settled'] and l['phase'] == 'forward' for l in d['sync_links'])).lower()"
}
node_link_lag() { cluster_eval "$1" "sum(l['lag_entries'] for l in d['sync_links'] if l['peer'] == '$2')"; }
node_feed_enabled() { cluster_eval "$1" "str(d['feed']['enabled']).lower()"; }
node_feed_head() { cluster_eval "$1" "d['feed']['head']"; }
node_feed_floor() { cluster_eval "$1" "d['feed']['floor']"; }
node_feed_consumer_count() { cluster_eval "$1" "len(d['feed']['consumers'])"; }
node_feed_cursor_of() {
  cluster_eval "$1" "next((c['cursor'] for c in d['feed']['consumers'] if c['peer'] == '$2'), 'none')"
}

internal_status() {
  dc exec -T "$1" curl -fsS http://localhost:7443/_internal/status 2>/dev/null
}

# Push-side request count from URL's node towards TARGET (host:port label),
# excluding the backfill_* operations the pull links themselves issue.
push_requests_to() {
  curl -fsS "$1/metrics" 2>/dev/null \
    | grep '^kura_replication_requests_total' \
    | grep "target=\"$2\"" \
    | grep -v 'operation="backfill_' \
    | awk '{ sum += $NF } END { printf "%.0f", sum + 0 }'
}

metric_series_count() {
  curl -fsS "$1/metrics" 2>/dev/null | grep -c "^$2" || true
}

# --- containers and logs ----------------------------------------------------

service_container_id() {
  dc ps -a -q "$1"
}

container_running() {
  docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null || printf 'unknown'
}

wait_for_service_exited() {
  local id status
  id="$(service_container_id "$1")"
  for _ in $(seq 1 120); do
    status="$(docker inspect --format '{{.State.Status}}' "$id" 2>/dev/null || true)"
    if [ "$status" = exited ]; then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for %s to exit (last status %s)\n' "$1" "${status:-unknown}" >&2
  return 1
}

service_log_count() {
  local service="$1" needle="$2" since="${3:-}"
  if [ -n "$since" ]; then
    dc logs --no-color --since "$since" "$service" 2>&1 | grep -c -- "$needle" || true
  else
    dc logs --no-color "$service" 2>&1 | grep -c -- "$needle" || true
  fi
}

# Log lines (message field only, plus the named fields) matching PATTERN,
# for failure evidence.
service_log_excerpt() {
  local service="$1" pattern="$2" since="${3:-}" limit="${4:-20}"
  if [ -n "$since" ]; then
    dc logs --no-color --since "$since" "$service" 2>&1
  else
    dc logs --no-color "$service" 2>&1
  fi | grep -E -- "$pattern" | grep -v 'peer status request failed' \
    | sed -E 's/,"target":.*$//' | tail -n "$limit"
}

# The `watermark` field of the newest "region backward pass starting" line
# since SINCE, or `none` when the pass started without a seeded watermark.
region_pass_watermark() {
  dc logs --no-color --since "$2" "$1" 2>&1 | python3 -c '
import json, sys
value = "none"
for line in sys.stdin:
    start = line.find("{")
    if start < 0:
        continue
    try:
        obj = json.loads(line[start:])
    except ValueError:
        continue
    if obj.get("message") == "region backward pass starting":
        found = obj.get("watermark")
        value = "none" if found is None else str(found)
print(value)
'
}

# --- keyvalue traffic --------------------------------------------------------

kv_put() {
  status_only -X PUT \
    "$1/api/cache/keyvalue?tenant_id=acme&namespace_id=$2" \
    -H "content-type: application/json" \
    -d "{\"cas_id\":\"$3\",\"entries\":[{\"value\":\"$4\"}]}"
}

kv_url() {
  printf '%s/api/cache/keyvalue/%s?tenant_id=acme&namespace_id=%s' "$1" "$3" "$2"
}

# PUT COUNT records `PREFIX-1..COUNT` with WORKERS parallel writers; prints
# the number of PUTs that did not answer 204.
kv_burst() {
  local url="$1" namespace="$2" prefix="$3" count="$4" workers="$5"
  seq 1 "$count" | xargs -P "$workers" -n 1 sh -c '
    curl -sS -o /dev/null -w "%{http_code}\n" -X PUT \
      "$0/api/cache/keyvalue?tenant_id=acme&namespace_id=$1" \
      -H "content-type: application/json" \
      -d "{\"cas_id\":\"$2-$3\",\"entries\":[{\"value\":\"$2-$3\"}]}" || echo curl-failed
  ' "$url" "$namespace" "$prefix" | grep -vc '^204$' || true
}

# GET every STEP-th record of `PREFIX-1..COUNT` (always including COUNT);
# prints how many did not answer 200.
kv_missing() {
  local url="$1" namespace="$2" prefix="$3" count="$4" step="$5" workers="$6"
  { seq 1 "$step" "$count"; printf '%s\n' "$count"; } | sort -un | xargs -P "$workers" -n 1 sh -c '
    curl -sS -o /dev/null -w "%{http_code}\n" \
      "$0/api/cache/keyvalue/$2-$3?tenant_id=acme&namespace_id=$1" || echo curl-failed
  ' "$url" "$namespace" "$prefix" | grep -vc '^200$' || true
}

wait_for_kv_present() {
  wait_for_contains "$(kv_url "$1" "$2" "$3")" "\"$4\"" "${5:-60}" "${6:-0.5}" >/dev/null
}

# ---------------------------------------------------------------------------

Describe 'pull replication between two replicas of one region'
  Include spec/e2e/support.sh

  setup_suite() {
    sync_setup_project kura-sync-replicas
    sync_build_nodes kura-a1 kura-a2 || return 1
    sync_start_nodes kura-a1 kura-a2 || return 1
    wait_for_node_ready "${KURA_A1_URL}" || return 1
    wait_for_node_ready "${KURA_A2_URL}" || return 1
    wait_for_ring_members "${KURA_A1_URL}" 2 || return 1
    wait_for_ring_members "${KURA_A2_URL}" 2 || return 1
    wait_for_output true 60 1 node_links_settled "${KURA_A1_URL}" >/dev/null || return 1
    wait_for_output true 60 1 node_links_settled "${KURA_A2_URL}" >/dev/null || return 1
    wait_for_region_roles "${KURA_A1_URL}" "${KURA_A2_URL}" || return 1
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'resolve_sync_nodes kura-a1 kura-a2'
  AfterAll 'teardown_suite'

  # B-1
  It 'converges a write from one replica to the other in under two seconds over the arrival feed with an empty outbox'
    # The link shape of design §3: one replica link each way, region-local,
    # and the lowest URL holds the (idle, single-region) gateway role.
    a1_links="$(node_links "${KURA_A1_URL}")"
    The variable a1_links should eq "replica:region-a>${A2_NODE_URL}"
    a2_links="$(node_links "${KURA_A2_URL}")"
    The variable a2_links should eq "replica:region-a>${A1_NODE_URL}"
    a1_gateway="$(node_gateway "${KURA_A1_URL}")"
    The variable a1_gateway should eq true
    a2_gateway="$(node_gateway "${KURA_A2_URL}")"
    The variable a2_gateway should eq false
    a1_feed="$(node_feed_enabled "${KURA_A1_URL}")"
    The variable a1_feed should eq true

    started="$(now_ms)"
    put_status="$(kv_put "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b1-forward b1-forward-value)"
    The variable put_status should eq 204
    capture_into forward_read \
      wait_for_contains "$(kv_url "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b1-forward)" '"b1-forward-value"' 100 0.02 || return 1
    forward_ms=$(( $(now_ms) - started ))
    record_measurement "B-1 a1->a2 converge_ms=${forward_ms}"
    The variable forward_read should include '"b1-forward-value"'
    forward_under_two_seconds=$((forward_ms < 2000 ? 1 : 0))
    The variable forward_under_two_seconds should eq 1

    # Bidirectionality is load-bearing (§2): the non-gateway's writes leave
    # through the same mechanism.
    started="$(now_ms)"
    reverse_status="$(kv_put "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b1-reverse b1-reverse-value)"
    The variable reverse_status should eq 204
    capture_into reverse_read \
      wait_for_contains "$(kv_url "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b1-reverse)" '"b1-reverse-value"' 100 0.02 || return 1
    reverse_ms=$(( $(now_ms) - started ))
    record_measurement "B-1 a2->a1 converge_ms=${reverse_ms}"
    The variable reverse_read should include '"b1-reverse-value"'
    reverse_under_two_seconds=$((reverse_ms < 2000 ? 1 : 0))
    The variable reverse_under_two_seconds should eq 1

    # Cursor lag sits at zero on both pullers once the pages applied ...
    capture_into a2_lag \
      wait_for_output 0 20 0.25 metric_sum "${KURA_A2_URL}" kura_sync_forward_cursor_lag_entries "peer=\"${A1_NODE_URL}\"" || return 1
    The variable a2_lag should eq 0
    capture_into a1_lag \
      wait_for_output 0 20 0.25 metric_sum "${KURA_A1_URL}" kura_sync_forward_cursor_lag_entries "peer=\"${A2_NODE_URL}\"" || return 1
    The variable a1_lag should eq 0
    # ... and nothing rides the push path between two pulling peers.
    a1_outbox="$(metric_sum "${KURA_A1_URL}" kura_outbox_messages)"
    The variable a1_outbox should eq 0
    a2_outbox="$(metric_sum "${KURA_A2_URL}" kura_outbox_messages)"
    The variable a2_outbox should eq 0
    a1_pushes_to_a2="$(push_requests_to "${KURA_A1_URL}" kura-a2.kura.internal:7443)"
    The variable a1_pushes_to_a2 should eq 0
    a2_pushes_to_a1="$(push_requests_to "${KURA_A2_URL}" kura-a1.kura.internal:7443)"
    The variable a2_pushes_to_a1 should eq 0
  End

  # B-2
  It 'catches a restarted replica up through the forward feed alone after ten thousand writes landed while it was stopped'
    dc stop kura-a2 >/dev/null 2>&1 || return 1
    wait_for_service_exited kura-a2 || return 1

    burst_failures="$(kv_burst "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b2 10000 16)"
    The variable burst_failures should eq 0
    # The feed retained every row for the absent sibling (cap is 1,000,000).
    head_after_burst="$(node_feed_head "${KURA_A1_URL}")"
    feed_holds_burst=$((head_after_burst >= 10000 ? 1 : 0))
    The variable feed_holds_burst should eq 1
    dropped_rows="$(metric_sum "${KURA_A1_URL}" kura_sync_forward_index_dropped_total)"
    The variable dropped_rows should eq 0

    dc up -d kura-a2 >/dev/null 2>&1 || return 1
    resolve_sync_nodes kura-a2
    wait_for_node_ready "${KURA_A2_URL}" || return 1
    capture_into a2_settled wait_for_output true 120 1 node_links_settled "${KURA_A2_URL}" || return 1
    The variable a2_settled should eq true
    capture_into a2_lag wait_for_output 0 120 1 node_link_lag "${KURA_A2_URL}" "${A1_NODE_URL}" || return 1
    The variable a2_lag should eq 0

    # Forward feed alone: no 410 on the fresh process, and no listing pages —
    # a backward pass is the only thing that lists the peer's index.
    fell_behind="$(metric_sum "${KURA_A2_URL}" kura_sync_forward_fell_behind_total)"
    The variable fell_behind should eq 0
    listing_pages="$(metric_sum "${KURA_A2_URL}" kura_backfill_listing_pages_total)"
    The variable listing_pages should eq 0

    missing_sample="$(kv_missing "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b2 10000 100 16)"
    The variable missing_sample should eq 0
    # The source trimmed its feed behind the sibling's cursor (§3.1).
    capture_into a1_feed_depth \
      wait_for_output 0 30 1 metric_sum "${KURA_A1_URL}" kura_sync_forward_index_entries || return 1
    The variable a1_feed_depth should eq 0
  End
End

Describe 'pull replication recovery when a replica falls off the arrival feed'
  Include spec/e2e/support.sh

  FEED_CAP=100

  setup_suite() {
    sync_setup_project kura-sync-feed-cap
    suite_env KURA_E2E_SYNC_FEED_MAX_ROWS "${FEED_CAP}"
    sync_build_nodes kura-a1 kura-a2 || return 1
    sync_start_nodes kura-a1 kura-a2 || return 1
    wait_for_node_ready "${KURA_A1_URL}" || return 1
    wait_for_node_ready "${KURA_A2_URL}" || return 1
    wait_for_ring_members "${KURA_A1_URL}" 2 || return 1
    wait_for_output true 60 1 node_links_settled "${KURA_A1_URL}" >/dev/null || return 1
    wait_for_output true 60 1 node_links_settled "${KURA_A2_URL}" >/dev/null || return 1
    wait_for_region_roles "${KURA_A1_URL}" "${KURA_A2_URL}" || return 1
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'resolve_sync_nodes kura-a1 kura-a2'
  AfterAll 'teardown_suite'

  # B-3
  It 'answers 410 to the stale cursor, re-bootstraps through a backward pass, and converges every record'
    seed_status="$(kv_put "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b3-seed b3-seed-value)"
    The variable seed_status should eq 204
    wait_for_kv_present "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b3-seed b3-seed-value 30 0.2 || return 1

    dc stop kura-a2 >/dev/null 2>&1 || return 1
    wait_for_service_exited kura-a2 || return 1

    burst_failures="$(kv_burst "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b3 1000 16)"
    The variable burst_failures should eq 0
    # Writes were never blocked by the cap: the oldest rows went instead.
    dropped_rows="$(metric_sum "${KURA_A1_URL}" kura_sync_forward_index_dropped_total)"
    dropped_at_cap=$((dropped_rows >= 1 ? 1 : 0))
    The variable dropped_at_cap should eq 1
    head="$(node_feed_head "${KURA_A1_URL}")"
    floor="$(node_feed_floor "${KURA_A1_URL}")"
    retained_within_cap=$(( (head - floor) <= FEED_CAP ? 1 : 0 ))
    The variable retained_within_cap should eq 1

    since="$(utc_now)"
    dc up -d kura-a2 >/dev/null 2>&1 || return 1
    resolve_sync_nodes kura-a2
    wait_for_http "${KURA_A2_URL}/up" 60 1 || return 1

    # The sibling's cursor is below the floor: exactly one 410, reason floor.
    capture_into fell_behind_floor \
      wait_for_metric_ge "${KURA_A2_URL}" kura_sync_forward_fell_behind_total 'reason="floor"' 1 60 1 || return 1
    The variable fell_behind_floor should eq 1
    wait_for_node_ready "${KURA_A2_URL}" || return 1
    capture_into a2_settled wait_for_output true 120 1 node_links_settled "${KURA_A2_URL}" || return 1
    The variable a2_settled should eq true
    fell_behind_total="$(metric_sum "${KURA_A2_URL}" kura_sync_forward_fell_behind_total)"
    The variable fell_behind_total should eq 1
    # Recovery = snapshot + backward pass + forward (§3.1): the pass listed
    # the peer's index, which the forward feed alone never does.
    listing_pages="$(metric_sum "${KURA_A2_URL}" kura_backfill_listing_pages_total)"
    backward_pass_ran=$((listing_pages >= 1 ? 1 : 0))
    The variable backward_pass_ran should eq 1
    rebootstraps="$(service_log_count kura-a2 'replica bootstrap: snapshot taken' "${since}")"
    The variable rebootstraps should eq 1

    missing="$(kv_missing "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b3 1000 1 16)"
    The variable missing should eq 0
    seed_after="$(curl -fsS "$(kv_url "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b3-seed)")"
    The variable seed_after should include '"b3-seed-value"'

    # The forward link is live again after the recovery.
    after_status="$(kv_put "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b3-after b3-after-value)"
    The variable after_status should eq 204
    wait_for_kv_present "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b3-after b3-after-value 30 0.2 || return 1
    capture_into a2_lag wait_for_output 0 30 0.5 node_link_lag "${KURA_A2_URL}" "${A1_NODE_URL}" || return 1
    The variable a2_lag should eq 0
  End
End

Describe 'drain gate of a departing replica'
  Include spec/e2e/support.sh

  # Budget minus margin bounds the sibling wait (§3.5). Short enough that an
  # expired gate fails the example in seconds; the exit-time assertion below
  # reads "took the timeout path" from this bound.
  DRAIN_BUDGET_MS=40000
  DRAIN_MARGIN_MS=5000
  LAGGED_WRITES=200

  setup_suite() {
    sync_setup_project kura-sync-drain
    suite_env KURA_E2E_DRAIN_COMPLETION_TIMEOUT_MS "${DRAIN_BUDGET_MS}"
    suite_env KURA_E2E_SYNC_DRAIN_MARGIN_MS "${DRAIN_MARGIN_MS}"
    sync_build_nodes kura-a1 kura-a2 || return 1
    sync_start_nodes kura-a1 kura-a2 || return 1
    wait_for_node_ready "${KURA_A1_URL}" || return 1
    wait_for_node_ready "${KURA_A2_URL}" || return 1
    wait_for_ring_members "${KURA_A1_URL}" 2 || return 1
    wait_for_output true 60 1 node_links_settled "${KURA_A1_URL}" >/dev/null || return 1
    wait_for_output true 60 1 node_links_settled "${KURA_A2_URL}" >/dev/null || return 1
    wait_for_region_roles "${KURA_A1_URL}" "${KURA_A2_URL}" || return 1
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  # B-4, as one function so the measured timings and — on failure — the
  # log evidence from both nodes land in the example output.
  run_drain_gate_check() {
    local a1_id head cursor burst_failures running term_started unpaused exited_at
    local exit_code reached timed_out missing since failed=0 gate_ms
    resolve_sync_nodes kura-a1 kura-a2

    [ "$(kv_put "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b4-seed b4-seed-value)" = 204 ] || {
      printf 'seed write failed\n'
      return 1
    }
    wait_for_kv_present "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b4-seed b4-seed-value 30 0.2 || return 1
    a1_id="$(service_container_id kura-a1)"

    # Freeze the sibling so it lags, then land writes it has not pulled.
    dc pause kura-a2 >/dev/null 2>&1 || { printf 'pause failed\n'; return 1; }
    burst_failures="$(kv_burst "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b4 "${LAGGED_WRITES}" 8)"
    head="$(node_feed_head "${KURA_A1_URL}")"
    cursor="$(node_feed_cursor_of "${KURA_A1_URL}" "${A2_NODE_URL}")"
    printf 'B-4 lagged_writes=%s burst_failures=%s feed_head=%s sibling_cursor=%s\n' \
      "${LAGGED_WRITES}" "$burst_failures" "$head" "$cursor"
    if [ "$burst_failures" != 0 ] || [ "$cursor" = none ] || [ "$cursor" -ge "$head" ]; then
      printf 'precondition failed: the sibling is not lagging behind the head\n'
      dc unpause kura-a2 >/dev/null 2>&1
      return 1
    fi

    since="$(utc_now)"
    dc kill -s SIGUSR1 kura-a1 >/dev/null 2>&1
    wait_for_status "${KURA_A1_URL}/ready" 503 20 0.5 >/dev/null || {
      printf 'node did not enter draining after SIGUSR1\n'
      dc unpause kura-a2 >/dev/null 2>&1
      return 1
    }
    term_started="$(now_ms)"
    dc kill -s SIGTERM kura-a1 >/dev/null 2>&1
    sleep 4
    running="$(container_running "$a1_id")"
    printf 'B-4 running_4s_after_sigterm=%s\n' "$running"

    dc unpause kura-a2 >/dev/null 2>&1
    unpaused="$(now_ms)"
    for _ in $(seq 1 120); do
      running="$(container_running "$a1_id")"
      [ "$running" = false ] && break
      sleep 0.5
    done
    exited_at="$(now_ms)"
    exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$a1_id" 2>/dev/null || printf 'unknown')"
    reached="$(service_log_count kura-a1 'sibling cursor reached the head before exit' "$since")"
    timed_out="$(service_log_count kura-a1 "exiting before the sibling's cursor reached the head" "$since")"
    missing="$(kv_missing "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b4 "${LAGGED_WRITES}" 1 16)"
    gate_ms=$((DRAIN_BUDGET_MS - DRAIN_MARGIN_MS))
    printf 'B-4 exit_after_unpause_ms=%s exit_after_sigterm_ms=%s running=%s exit_code=%s reached_head_lines=%s drain_timeout_lines=%s sibling_missing=%s\n' \
      "$((exited_at - unpaused))" "$((exited_at - term_started))" "$running" "$exit_code" \
      "$reached" "$timed_out" "$missing"
    record_measurement "B-4 exit_after_unpause_ms=$((exited_at - unpaused)) exit_after_sigterm_ms=$((exited_at - term_started)) drain_timeout_lines=${timed_out}"

    if [ "$running" != false ]; then
      printf 'FAIL: the node was still running %s ms after SIGTERM\n' "$((exited_at - term_started))"
      failed=1
    fi
    if [ $((exited_at - term_started)) -ge "$gate_ms" ]; then
      printf 'FAIL: the exit took the drain-timeout path (>= budget - margin = %s ms)\n' "$gate_ms"
      failed=1
    fi
    if [ "$reached" != 1 ]; then
      printf 'FAIL: expected one "sibling cursor reached the head before exit" line, got %s\n' "$reached"
      failed=1
    fi
    if [ "$timed_out" != 0 ]; then
      printf 'FAIL: kura_sync_forward_drain_timeout_total was recorded (%s line(s))\n' "$timed_out"
      failed=1
    fi
    if [ "$missing" != 0 ]; then
      printf 'FAIL: %s of the lagged writes never reached the sibling\n' "$missing"
      failed=1
    fi
    if [ "$failed" = 1 ]; then
      printf -- '--- kura-a1 (departing) log excerpt\n'
      service_log_excerpt kura-a1 'SIGUSR1|sibling|drain|exiting|shutdown|budget' "$since"
      printf -- '--- kura-a2 (lagging sibling) log excerpt\n'
      service_log_excerpt kura-a2 'forward|pull link|bootstrap|fell|roles derived' "$since"
      return 1
    fi
  }

  It 'holds the exit of a terminating replica until the lagging sibling has pulled its head'
    When call run_drain_gate_check
    The status should be success
    The output should include 'B-4 exit_after_unpause_ms='
    # A failing verdict prints its reason and both nodes' log excerpts; this
    # expectation puts that evidence into the report.
    The output should not include 'FAIL:'
  End
End

Describe 'pull replication across two regions of two replicas'
  Include spec/e2e/support.sh

  # Two seconds, not ten minutes: the failover example reads "no full
  # re-walk" from what the new gateway's buffered backward pass lists.
  PASS_START_BUFFER_MS=2000
  OLD_BURST=300

  setup_suite() {
    sync_setup_project kura-sync-regions
    suite_env KURA_E2E_SYNC_PASS_START_BUFFER_MS "${PASS_START_BUFFER_MS}"
    sync_build_nodes kura-a1 kura-a2 kura-b1 kura-b2 || return 1
    sync_start_nodes kura-a1 kura-a2 kura-b1 kura-b2 || return 1
    local url
    for url in "${KURA_A1_URL}" "${KURA_A2_URL}" "${KURA_B1_URL}" "${KURA_B2_URL}"; do
      wait_for_node_ready "$url" || return 1
    done
    for url in "${KURA_A1_URL}" "${KURA_A2_URL}" "${KURA_B1_URL}" "${KURA_B2_URL}"; do
      wait_for_ring_members "$url" 4 || return 1
    done
    wait_for_output true 60 1 node_gateway "${KURA_A1_URL}" >/dev/null || return 1
    wait_for_output true 60 1 node_gateway "${KURA_B1_URL}" >/dev/null || return 1
    for url in "${KURA_A1_URL}" "${KURA_A2_URL}" "${KURA_B1_URL}" "${KURA_B2_URL}"; do
      wait_for_output true 120 1 node_links_settled "$url" >/dev/null || return 1
    done
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'resolve_sync_nodes kura-a1 kura-a2 kura-b1 kura-b2'
  AfterAll 'teardown_suite'

  # B-5
  It 'delivers a write from a non-gateway of one region to the non-gateway of the other, over gateway links only'
    # Topology of §2: gateways carry a replica link and the cross-region
    # link; non-gateways carry their sibling link and nothing else.
    a1_links="$(node_links "${KURA_A1_URL}")"
    The variable a1_links should eq "region:region-b>${B1_NODE_URL} replica:region-a>${A2_NODE_URL}"
    a2_links="$(node_links "${KURA_A2_URL}")"
    The variable a2_links should eq "replica:region-a>${A1_NODE_URL}"
    b1_links="$(node_links "${KURA_B1_URL}")"
    The variable b1_links should eq "region:region-a>${A1_NODE_URL} replica:region-b>${B2_NODE_URL}"
    b2_links="$(node_links "${KURA_B2_URL}")"
    The variable b2_links should eq "replica:region-b>${B1_NODE_URL}"
    a2_gateway="$(node_gateway "${KURA_A2_URL}")"
    The variable a2_gateway should eq false
    b2_gateway="$(node_gateway "${KURA_B2_URL}")"
    The variable b2_gateway should eq false
    a2_region_links="$(metric_sum "${KURA_A2_URL}" kura_sync_pull_links 'link="region"')"
    The variable a2_region_links should eq 0
    b2_region_links="$(metric_sum "${KURA_B2_URL}" kura_sync_pull_links 'link="region"')"
    The variable b2_region_links should eq 0
    a1_region_links="$(metric_sum "${KURA_A1_URL}" kura_sync_pull_links 'link="region"')"
    The variable a1_region_links should eq 1
    b1_region_links="$(metric_sum "${KURA_B1_URL}" kura_sync_pull_links 'link="region"')"
    The variable b1_region_links should eq 1
    a1_role_gauge="$(metric_sum "${KURA_A1_URL}" kura_gateway_role 'state="gateway"')"
    The variable a1_role_gauge should eq 1
    b2_role_gauge="$(metric_sum "${KURA_B2_URL}" kura_gateway_role 'state="gateway"')"
    The variable b2_role_gauge should eq 0

    # a2 -> a1 (feed) -> b1 (region link) -> b2 (feed).
    started="$(now_ms)"
    put_status="$(kv_put "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b5-cross b5-cross-value)"
    The variable put_status should eq 204
    capture_into cross_read \
      wait_for_contains "$(kv_url "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b5-cross)" '"b5-cross-value"' 300 0.1 || return 1
    cross_ms=$(( $(now_ms) - started ))
    record_measurement "B-5 a2->b2 converge_ms=${cross_ms}"
    The variable cross_read should include '"b5-cross-value"'
    wait_for_kv_present "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b5-cross b5-cross-value 30 0.2 || return 1
    wait_for_kv_present "${KURA_B1_URL}" "${SYNC_NAMESPACE}" b5-cross b5-cross-value 30 0.2 || return 1

    # And back the other way.
    started="$(now_ms)"
    reverse_status="$(kv_put "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b5-reverse b5-reverse-value)"
    The variable reverse_status should eq 204
    capture_into reverse_read \
      wait_for_contains "$(kv_url "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b5-reverse)" '"b5-reverse-value"' 300 0.1 || return 1
    reverse_ms=$(( $(now_ms) - started ))
    record_measurement "B-5 b2->a2 converge_ms=${reverse_ms}"
    The variable reverse_read should include '"b5-reverse-value"'

    # Each gateway now holds a watermark for the other region (§4.3), and
    # nothing was pushed anywhere.
    b1_watermark_series="$(metric_series_count "${KURA_B1_URL}" 'kura_region_watermark_age_seconds{region="region-a"}')"
    The variable b1_watermark_series should eq 1
    a1_watermark_series="$(metric_series_count "${KURA_A1_URL}" 'kura_region_watermark_age_seconds{region="region-b"}')"
    The variable a1_watermark_series should eq 1
    outbox_total=$(( $(metric_sum "${KURA_A1_URL}" kura_outbox_messages) + $(metric_sum "${KURA_A2_URL}" kura_outbox_messages) + $(metric_sum "${KURA_B1_URL}" kura_outbox_messages) + $(metric_sum "${KURA_B2_URL}" kura_outbox_messages) ))
    The variable outbox_total should eq 0
  End

  # B-7
  It 'propagates a namespace delete from one region to every node'
    doomed_1="$(kv_put "${KURA_A1_URL}" doomed b7-doomed-1 b7-doomed-value)"
    The variable doomed_1 should eq 204
    doomed_2="$(kv_put "${KURA_A1_URL}" doomed b7-doomed-2 b7-doomed-value)"
    The variable doomed_2 should eq 204
    keep_status="$(kv_put "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b7-keep b7-keep-value)"
    The variable keep_status should eq 204
    local_url=""
    for local_url in "${KURA_A2_URL}" "${KURA_B1_URL}" "${KURA_B2_URL}"; do
      wait_for_kv_present "$local_url" doomed b7-doomed-2 b7-doomed-value 60 0.2 || return 1
      wait_for_kv_present "$local_url" "${SYNC_NAMESPACE}" b7-keep b7-keep-value 60 0.2 || return 1
    done

    delete_status="$(status_only -X DELETE "${KURA_A1_URL}/api/cache/clean?tenant_id=acme&namespace_id=doomed")"
    The variable delete_status should eq 204

    # The tombstone is a feed row inside region A and an index row across
    # the region link (§4.7): applied on the sibling, the remote gateway and
    # the remote non-gateway alike.
    capture_into a2_gone wait_for_status "$(kv_url "${KURA_A2_URL}" doomed b7-doomed-1)" 404 120 0.5 || return 1
    The variable a2_gone should eq 404
    capture_into b1_gone wait_for_status "$(kv_url "${KURA_B1_URL}" doomed b7-doomed-1)" 404 120 0.5 || return 1
    The variable b1_gone should eq 404
    capture_into b2_gone wait_for_status "$(kv_url "${KURA_B2_URL}" doomed b7-doomed-2)" 404 120 0.5 || return 1
    The variable b2_gone should eq 404
    b2_gone_1="$(status_only "$(kv_url "${KURA_B2_URL}" doomed b7-doomed-1)")"
    The variable b2_gone_1 should eq 404
    a1_gone="$(status_only "$(kv_url "${KURA_A1_URL}" doomed b7-doomed-2)")"
    The variable a1_gone should eq 404
    # Other namespaces are untouched.
    b2_keep="$(status_only "$(kv_url "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b7-keep)")"
    The variable b2_keep should eq 200
  End

  # B-6
  It 'moves the gateway role to the sibling when the gateway restarts, keeping the region watermark'
    # Old data in region A, converged everywhere, then a marker write that
    # moves region B's watermark for region-a clearly past the burst.
    burst_failures="$(kv_burst "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b6-old "${OLD_BURST}" 16)"
    The variable burst_failures should eq 0
    missing_on_b2="$(kv_missing "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b6-old "${OLD_BURST}" 10 16)"
    for _ in $(seq 1 120); do
      [ "$missing_on_b2" = 0 ] && break
      sleep 0.5
      missing_on_b2="$(kv_missing "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b6-old "${OLD_BURST}" 10 16)"
    done
    The variable missing_on_b2 should eq 0
    sleep 5
    marker_status="$(kv_put "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b6-marker b6-marker-value)"
    The variable marker_status should eq 204
    wait_for_kv_present "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b6-marker b6-marker-value 60 0.2 || return 1
    sleep 3

    listed_before="$(metric_sum "${KURA_B2_URL}" kura_backfill_listed_tuples_total)"
    changes_before="$(metric_sum "${KURA_B2_URL}" kura_gateway_role_changes_total)"
    since="$(utc_now)"

    dc stop kura-b1 >/dev/null 2>&1 || return 1
    wait_for_service_exited kura-b1 || return 1

    # Overlap over gaps (§2.4): the surviving replica takes the role, and
    # region A's gateway re-points its cross-region link at it.
    capture_into b2_gateway wait_for_output true 60 1 node_gateway "${KURA_B2_URL}" || return 1
    The variable b2_gateway should eq true
    capture_into b2_links wait_for_output "region:region-a>${A1_NODE_URL}" 60 1 node_links "${KURA_B2_URL}" || return 1
    The variable b2_links should eq "region:region-a>${A1_NODE_URL}"
    capture_into a1_links \
      wait_for_output "region:region-b>${B2_NODE_URL} replica:region-a>${A2_NODE_URL}" 60 1 node_links "${KURA_A1_URL}" || return 1
    The variable a1_links should eq "region:region-b>${B2_NODE_URL} replica:region-a>${A2_NODE_URL}"
    capture_into b2_settled wait_for_output true 120 1 node_links_settled "${KURA_B2_URL}" || return 1
    The variable b2_settled should eq true
    capture_into a1_settled wait_for_output true 120 1 node_links_settled "${KURA_A1_URL}" || return 1
    The variable a1_settled should eq true

    # Watermark preserved: the promoted gateway's backward pass started from
    # the region watermark it inherited over the feed (§4.3), not from
    # nothing, so it listed at most the buffer's worth rather than the burst.
    pass_watermark="$(region_pass_watermark kura-b2 "${since}")"
    The variable pass_watermark should not eq none
    listed_after="$(metric_sum "${KURA_B2_URL}" kura_backfill_listed_tuples_total)"
    relisted=$((listed_after - listed_before))
    rewalk_bounded=$((relisted < OLD_BURST ? 1 : 0))
    The variable rewalk_bounded should eq 1

    # Region A's writes keep flowing through the new gateway.
    during_status="$(kv_put "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b6-during b6-during-value)"
    The variable during_status should eq 204
    wait_for_kv_present "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b6-during b6-during-value 60 0.2 || return 1

    # The old gateway returns on its volume and, once serving, takes the
    # role back by the lowest-URL rule; the sibling steps down.
    dc up -d kura-b1 >/dev/null 2>&1 || return 1
    resolve_sync_nodes kura-b1
    wait_for_node_ready "${KURA_B1_URL}" || return 1
    capture_into b1_gateway wait_for_output true 90 1 node_gateway "${KURA_B1_URL}" || return 1
    The variable b1_gateway should eq true
    capture_into b2_standby wait_for_output false 60 1 node_gateway "${KURA_B2_URL}" || return 1
    The variable b2_standby should eq false
    capture_into b1_links \
      wait_for_output "region:region-a>${A1_NODE_URL} replica:region-b>${B2_NODE_URL}" 60 1 node_links "${KURA_B1_URL}" || return 1
    The variable b1_links should eq "region:region-a>${A1_NODE_URL} replica:region-b>${B2_NODE_URL}"
    capture_into b2_links_after wait_for_output "replica:region-b>${B1_NODE_URL}" 60 1 node_links "${KURA_B2_URL}" || return 1
    The variable b2_links_after should eq "replica:region-b>${B1_NODE_URL}"
    capture_into a1_links_after \
      wait_for_output "region:region-b>${B1_NODE_URL} replica:region-a>${A2_NODE_URL}" 60 1 node_links "${KURA_A1_URL}" || return 1
    The variable a1_links_after should eq "region:region-b>${B1_NODE_URL} replica:region-a>${A2_NODE_URL}"
    local_url=""
    for local_url in "${KURA_A1_URL}" "${KURA_B1_URL}" "${KURA_B2_URL}"; do
      wait_for_output true 120 1 node_links_settled "$local_url" >/dev/null || return 1
    done
    changes_after="$(metric_sum "${KURA_B2_URL}" kura_gateway_role_changes_total)"
    role_round_trip=$((changes_after - changes_before))
    The variable role_round_trip should eq 2

    # Everything written across the failover is on the returned gateway.
    b1_missing_during="$(status_only "$(kv_url "${KURA_B1_URL}" "${SYNC_NAMESPACE}" b6-during)")"
    The variable b1_missing_during should eq 200
    after_status="$(kv_put "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b6-after b6-after-value)"
    The variable after_status should eq 204
    wait_for_kv_present "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b6-after b6-after-value 60 0.2 || return 1
    wait_for_kv_present "${KURA_B1_URL}" "${SYNC_NAMESPACE}" b6-after b6-after-value 60 0.2 || return 1
  End
End

Describe 'mixed mesh with pull enabled in one region only'
  Include spec/e2e/support.sh

  setup_suite() {
    sync_setup_project kura-sync-mixed
    suite_env KURA_E2E_SYNC_PULL_B false
    sync_build_nodes kura-a1 kura-a2 kura-b1 kura-b2 || return 1
    sync_start_nodes kura-a1 kura-a2 kura-b1 kura-b2 || return 1
    local url
    for url in "${KURA_A1_URL}" "${KURA_A2_URL}" "${KURA_B1_URL}" "${KURA_B2_URL}"; do
      wait_for_node_ready "$url" || return 1
    done
    for url in "${KURA_A1_URL}" "${KURA_A2_URL}" "${KURA_B1_URL}" "${KURA_B2_URL}"; do
      wait_for_ring_members "$url" 4 || return 1
    done
    wait_for_output true 120 1 node_links_settled "${KURA_A1_URL}" >/dev/null || return 1
    wait_for_output true 120 1 node_links_settled "${KURA_A2_URL}" >/dev/null || return 1
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'resolve_sync_nodes kura-a1 kura-a2 kura-b1 kura-b2'
  AfterAll 'teardown_suite'

  # B-8
  It 'keeps the push region pushing while the pull region pulls from its own peers, and converges both ways'
    # The flip is per node and advertised (§5.2, D-16): region B is on push
    # and opens no links; region A pulls from its own pulling peer and has
    # no remote gateway to read, since nobody else pulls.
    capture_into b1_internal internal_status kura-b1 || return 1
    The variable b1_internal should include '"pulling":false'
    capture_into a1_internal internal_status kura-a1 || return 1
    The variable a1_internal should include '"pulling":true'
    b1_pulling="$(node_pulling "${KURA_B1_URL}")"
    The variable b1_pulling should eq false
    b1_links="$(node_links "${KURA_B1_URL}")"
    The variable b1_links should eq none
    b2_links="$(node_links "${KURA_B2_URL}")"
    The variable b2_links should eq none
    b1_gateway="$(node_gateway "${KURA_B1_URL}")"
    The variable b1_gateway should eq false
    a1_links="$(node_links "${KURA_A1_URL}")"
    The variable a1_links should eq "replica:region-a>${A2_NODE_URL}"
    a2_links="$(node_links "${KURA_A2_URL}")"
    The variable a2_links should eq "replica:region-a>${A1_NODE_URL}"
    a1_region_links="$(metric_sum "${KURA_A1_URL}" kura_sync_pull_links 'link="region"')"
    The variable a1_region_links should eq 0

    # Region B still pushes: its write lands on every node.
    from_b="$(kv_put "${KURA_B1_URL}" "${SYNC_NAMESPACE}" b8-from-b b8-from-b-value)"
    The variable from_b should eq 204
    wait_for_kv_present "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b8-from-b b8-from-b-value 60 0.2 || return 1
    wait_for_kv_present "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b8-from-b b8-from-b-value 60 0.2 || return 1
    wait_for_kv_present "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b8-from-b b8-from-b-value 60 0.2 || return 1
    # Region A pulls inside and pushes out: a non-gateway write reaches its
    # sibling over the feed and region B over the legacy push path.
    from_a="$(kv_put "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b8-from-a b8-from-a-value)"
    The variable from_a should eq 204
    wait_for_kv_present "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b8-from-a b8-from-a-value 60 0.2 || return 1
    wait_for_kv_present "${KURA_B1_URL}" "${SYNC_NAMESPACE}" b8-from-a b8-from-a-value 60 0.2 || return 1
    wait_for_kv_present "${KURA_B2_URL}" "${SYNC_NAMESPACE}" b8-from-a b8-from-a-value 60 0.2 || return 1

    # On the wire: B pushed into A; A pushed into B; A never pushed to its
    # pulling sibling (the per-peer rule), whose copy came over the feed.
    b1_pushes_to_a1="$(push_requests_to "${KURA_B1_URL}" kura-a1.kura.internal:7443)"
    b_pushed=$((b1_pushes_to_a1 >= 1 ? 1 : 0))
    The variable b_pushed should eq 1
    a2_pushes_to_b1="$(push_requests_to "${KURA_A2_URL}" kura-b1.kura.internal:7443)"
    a_pushed=$((a2_pushes_to_b1 >= 1 ? 1 : 0))
    The variable a_pushed should eq 1
    a2_pushes_to_a1="$(push_requests_to "${KURA_A2_URL}" kura-a1.kura.internal:7443)"
    The variable a2_pushes_to_a1 should eq 0
    a1_pushes_to_a2="$(push_requests_to "${KURA_A1_URL}" kura-a2.kura.internal:7443)"
    The variable a1_pushes_to_a2 should eq 0
    capture_into b1_outbox wait_for_output 0 30 1 metric_sum "${KURA_B1_URL}" kura_outbox_messages || return 1
    The variable b1_outbox should eq 0
    capture_into a2_outbox wait_for_output 0 30 1 metric_sum "${KURA_A2_URL}" kura_outbox_messages || return 1
    The variable a2_outbox should eq 0
  End
End

Describe 'serverless mesh of a region of one beside a two-replica region'
  Include spec/e2e/support.sh

  setup_suite() {
    sync_setup_project kura-sync-serverless
    sync_build_nodes kura-a1 kura-a2 kura-solo || return 1
    sync_start_nodes kura-a1 kura-a2 kura-solo || return 1
    local url
    for url in "${KURA_A1_URL}" "${KURA_A2_URL}" "${KURA_SOLO_URL}"; do
      wait_for_node_ready "$url" || return 1
    done
    for url in "${KURA_A1_URL}" "${KURA_A2_URL}" "${KURA_SOLO_URL}"; do
      wait_for_ring_members "$url" 3 || return 1
    done
    for url in "${KURA_A1_URL}" "${KURA_A2_URL}" "${KURA_SOLO_URL}"; do
      wait_for_output true 120 1 node_links_settled "$url" >/dev/null || return 1
    done
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'resolve_sync_nodes kura-a1 kura-a2 kura-solo'
  AfterAll 'teardown_suite'

  # B-10
  It 'derives exactly one gateway per region locally'
    capture_into a1_gateway wait_for_output true 30 1 node_gateway "${KURA_A1_URL}" || return 1
    The variable a1_gateway should eq true
    capture_into solo_gateway wait_for_output true 30 1 node_gateway "${KURA_SOLO_URL}" || return 1
    The variable solo_gateway should eq true
    capture_into a2_gateway wait_for_output false 30 1 node_gateway "${KURA_A2_URL}" || return 1
    The variable a2_gateway should eq false
    region_a_gateways=$(( $(metric_sum "${KURA_A1_URL}" kura_gateway_role 'state="gateway"') + $(metric_sum "${KURA_A2_URL}" kura_gateway_role 'state="gateway"') ))
    The variable region_a_gateways should eq 1
    region_solo_gateways="$(metric_sum "${KURA_SOLO_URL}" kura_gateway_role 'state="gateway"')"
    The variable region_solo_gateways should eq 1
    # The clique (§2): gateways read each other; the non-gateway reads its
    # sibling and nothing across the boundary.
    solo_links="$(node_links "${KURA_SOLO_URL}")"
    The variable solo_links should eq "region:region-a>${A1_NODE_URL}"
    a1_links="$(node_links "${KURA_A1_URL}")"
    The variable a1_links should eq "region:region-solo>${SOLO_NODE_URL} replica:region-a>${A2_NODE_URL}"
    a2_links="$(node_links "${KURA_A2_URL}")"
    The variable a2_links should eq "replica:region-a>${A1_NODE_URL}"
    # Roles were derived from the membership view alone: nothing published.
    solo_internal="$(internal_status kura-solo)"
    The variable solo_internal should include '"pulling":true'
    The variable solo_internal should include '"region":"region-solo"'
  End

  # B-9
  It 'pulls the region of one through the gateway link with no arrival feed on the singleton'
    # A region of one carries no feed (§3.1): nobody asks it for a head.
    solo_feed="$(node_feed_enabled "${KURA_SOLO_URL}")"
    The variable solo_feed should eq false
    solo_consumers="$(node_feed_consumer_count "${KURA_SOLO_URL}")"
    The variable solo_consumers should eq 0
    a1_feed="$(node_feed_enabled "${KURA_A1_URL}")"
    The variable a1_feed should eq true
    a2_feed="$(node_feed_enabled "${KURA_A2_URL}")"
    The variable a2_feed should eq true

    # solo -> a1 (region link) -> a2 (feed).
    started="$(now_ms)"
    from_solo="$(kv_put "${KURA_SOLO_URL}" "${SYNC_NAMESPACE}" b9-from-solo b9-from-solo-value)"
    The variable from_solo should eq 204
    capture_into a2_read \
      wait_for_contains "$(kv_url "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b9-from-solo)" '"b9-from-solo-value"' 300 0.1 || return 1
    record_measurement "B-9 solo->a2 converge_ms=$(( $(now_ms) - started ))"
    The variable a2_read should include '"b9-from-solo-value"'
    wait_for_kv_present "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b9-from-solo b9-from-solo-value 30 0.2 || return 1
    # a2 -> a1 (feed) -> solo (region link), and a gateway write directly.
    from_a2="$(kv_put "${KURA_A2_URL}" "${SYNC_NAMESPACE}" b9-from-a2 b9-from-a2-value)"
    The variable from_a2 should eq 204
    wait_for_kv_present "${KURA_SOLO_URL}" "${SYNC_NAMESPACE}" b9-from-a2 b9-from-a2-value 60 0.1 || return 1
    from_a1="$(kv_put "${KURA_A1_URL}" "${SYNC_NAMESPACE}" b9-from-a1 b9-from-a1-value)"
    The variable from_a1 should eq 204
    wait_for_kv_present "${KURA_SOLO_URL}" "${SYNC_NAMESPACE}" b9-from-a1 b9-from-a1-value 60 0.1 || return 1

    # Still no feed on the singleton after traffic in both directions, and
    # no push traffic anywhere in the mesh.
    solo_feed_after="$(node_feed_enabled "${KURA_SOLO_URL}")"
    The variable solo_feed_after should eq false
    solo_pushes_to_a1="$(push_requests_to "${KURA_SOLO_URL}" kura-a1.kura.internal:7443)"
    The variable solo_pushes_to_a1 should eq 0
    a1_pushes_to_solo="$(push_requests_to "${KURA_A1_URL}" kura-solo.kura.internal:7443)"
    The variable a1_pushes_to_solo should eq 0
    outbox_total=$(( $(metric_sum "${KURA_A1_URL}" kura_outbox_messages) + $(metric_sum "${KURA_A2_URL}" kura_outbox_messages) + $(metric_sum "${KURA_SOLO_URL}" kura_outbox_messages) ))
    The variable outbox_total should eq 0
  End
End

Describe 'one-way membership between two pulling nodes'
  Include spec/e2e/support.sh

  setup_suite() {
    sync_setup_project kura-sync-one-way
    sync_build_nodes kura-d1 kura-d2 || return 1
    sync_start_nodes kura-d1 kura-d2 || return 1
    wait_for_node_ready "${KURA_D1_URL}" || return 1
    wait_for_node_ready "${KURA_D2_URL}" || return 1
    wait_for_ring_members "${KURA_D2_URL}" 2 || return 1
    wait_for_output true 60 1 node_links_settled "${KURA_D2_URL}" >/dev/null || return 1
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'resolve_sync_nodes kura-d1 kura-d2'
  AfterAll 'teardown_suite'

  # B-11
  It 'keeps pushing to a pulling peer that cannot dial back while pulling from it'
    # The one-way view (design §11.2): d2 lists d1, so it probes it and
    # names it; d1 lists nobody, so its own advertised view is empty and it
    # can never learn that d2 exists.
    capture_into d1_internal internal_status kura-d1 || return 1
    The variable d1_internal should include '"pulling":true'
    The variable d1_internal should include '"peers":[]'
    capture_into d2_internal internal_status kura-d2 || return 1
    The variable d2_internal should include '"pulling":true'
    The variable d2_internal should include "\"peers\":[\"${D1_NODE_URL}\"]"
    d1_links="$(node_links "${KURA_D1_URL}")"
    The variable d1_links should eq none
    d2_links="$(node_links "${KURA_D2_URL}")"
    The variable d2_links should eq "replica:region-d>${D1_NODE_URL}"

    # d1 -> d2 by pull: d2 reads d1's arrival feed.
    from_d1="$(kv_put "${KURA_D1_URL}" "${SYNC_NAMESPACE}" b11-from-d1 b11-from-d1-value)"
    The variable from_d1 should eq 204
    capture_into d2_read \
      wait_for_contains "$(kv_url "${KURA_D2_URL}" "${SYNC_NAMESPACE}" b11-from-d1)" '"b11-from-d1-value"' 300 0.1 || return 1
    The variable d2_read should include '"b11-from-d1-value"'

    # d2 -> d1 by push: nothing on d1 pulls, so the exception is the only
    # leg this direction has.
    from_d2="$(kv_put "${KURA_D2_URL}" "${SYNC_NAMESPACE}" b11-from-d2 b11-from-d2-value)"
    The variable from_d2 should eq 204
    wait_for_kv_present "${KURA_D1_URL}" "${SYNC_NAMESPACE}" b11-from-d2 b11-from-d2-value 60 0.2 || return 1
    d2_pushes_to_d1="$(push_requests_to "${KURA_D2_URL}" kura-d1.kura.internal:7443)"
    d2_pushed=$((d2_pushes_to_d1 >= 1 ? 1 : 0))
    The variable d2_pushed should eq 1
    capture_into d2_outbox wait_for_output 0 30 1 metric_sum "${KURA_D2_URL}" kura_outbox_messages || return 1
    The variable d2_outbox should eq 0
    d1_outbox="$(metric_sum "${KURA_D1_URL}" kura_outbox_messages)"
    The variable d1_outbox should eq 0
  End
End
