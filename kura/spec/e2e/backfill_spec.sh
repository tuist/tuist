# shellcheck shell=bash

# End-to-end checks for the recency-first backfill walker, one per origin
# incident shape:
#
#   - mid-pass restart: a node restart during backfill re-fetches only the
#     unapplied tail (the 2026-07 "~93% of a multi-hour pass lost to a
#     restart" class);
#   - listing/fetch skew: entries deleted between the listing and bodies
#     phases resolve absent without failing the pass (R13);
#   - throughput sanity: measured and logged to feed the deferred
#     KURA_BACKFILL_BATCH_BYTES default, with only a generous floor asserted;
#   - capacity completion: a cold node with an undersized ring backfilling
#     from TWO sources completes via the marginal trade with ~zero evictions
#     and the newest ring-worth retained (the #12047 CAS-thrash shape).
#     Opt-in via KURA_E2E_BACKFILL_CAPACITY=1 — it moves multiple GiB because
#     segments seal at the compiled 512 MiB ceiling and the ring floor is 5
#     segments, so an "undersized ring" cannot be produced with small data.
#
# All suites run under spec/e2e/docker-compose.backfill.yml.
# There is no env-armable failpoint mechanism in the release binary (the
# FailpointSet setters are cfg(test)-only), so the restart point is pinned
# instead by bandwidth-shaping the source and polling the requester's applied
# byte counter: the assertions are chosen to hold at every admissible kill
# point at or after the known applied set, which keeps the check deterministic
# without a raw "listing pages only" claim (explicitly forbidden by the plan).

Describe 'backfill pass fault tolerance'
  Include spec/e2e/support.sh

  # Entry geometry for the restart check. The three "big" bodies are written
  # last, so the newest-first walk applies them first; each fills one bodies
  # batch alone (KURA_E2E_BACKFILL_BATCH_BYTES == BIG_BYTES). The tail is
  # written first (older), totals less than one big body plus slack, and is
  # what a restart may legitimately re-fetch. Any re-fetch of a big body blows
  # the post-restart byte bound by construction.
  BIG_COUNT=3
  BIG_BYTES=16777216
  TAIL_COUNT=192
  TAIL_BYTES=65536
  TAIL_TOTAL_BYTES=$((TAIL_COUNT * TAIL_BYTES))
  ALL_BIGS_APPLIED_BYTES=$((BIG_COUNT * BIG_BYTES))
  REWALK_BODIES_BYTES_BOUND=$((TAIL_TOTAL_BYTES + 2097152))

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.discovery.yml"
      -f "${PROJECT_ROOT}/spec/e2e/docker-compose.backfill.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-backfill-faults
    ephemeral_ports KURA_US_PORT KURA_US_2_PORT TEMPO_PORT OTLP_PORT
    # 2 MiB/s source-side shaping holds a pass open for tens of seconds so the
    # restart and the delete land mid-pass instead of racing a sub-second
    # transfer; one 16 MiB batch bound makes each big body its own batch.
    suite_env KURA_E2E_REPLICATION_BW_BYTES_PER_SECOND 2097152
    suite_env KURA_E2E_BACKFILL_BATCH_BYTES "${BIG_BYTES}"

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    if [ "${KURA_E2E_SKIP_BUILD:-0}" != "1" ]; then
      dc build kura-us kura-us-2 >/dev/null 2>&1
    fi
  }

  reset_cluster() {
    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc up -d kura-us >/dev/null 2>&1
    resolve_http_node KURA_US kura-us
    wait_for_http "${KURA_US_URL}/up"
    capture_into us_up wait_for_contains "${KURA_US_URL}/up" '"ring_members":1' || return 1
    [[ "${us_up}" == *'"ring_members":1'* ]]
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'reset_cluster'
  AfterAll 'teardown_suite'

  upload_cas_batch() {
    local prefix="$1" count="$2" path="$3" failures=0 index status
    for index in $(seq 1 "$count"); do
      status="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/cas/${prefix}-${index}?tenant_id=acme&namespace_id=ios" \
        -H "content-type: application/octet-stream" \
        --data-binary "@${path}")"
      if [ "$status" != 204 ]; then
        failures=$((failures + 1))
      fi
    done
    printf '%s' "$failures"
  }

  count_cas_status_mismatches() {
    local base_url="$1" prefix="$2" count="$3" expected="$4" mismatches=0 index status
    for index in $(seq 1 "$count"); do
      status="$(status_only \
        "${base_url}/api/cache/cas/${prefix}-${index}?tenant_id=acme&namespace_id=ios")"
      if [ "$status" != "$expected" ]; then
        mismatches=$((mismatches + 1))
      fi
    done
    printf '%s' "$mismatches"
  }

  It 'resumes after a mid-pass restart without re-fetching applied bodies'
    tail_block="${SUITE_TMP_DIR}/tail.bin"
    big_block="${SUITE_TMP_DIR}/big.bin"
    dd if=/dev/urandom of="${tail_block}" bs="${TAIL_BYTES}" count=1 2>/dev/null
    dd if=/dev/urandom of="${big_block}" bs=1048576 count=$((BIG_BYTES / 1048576)) 2>/dev/null

    # Tail first (older versions), bigs last (newest): the newest-first walk
    # applies the bigs before any tail body.
    tail_upload_failures="$(upload_cas_batch restart-tail "${TAIL_COUNT}" "${tail_block}")"
    The variable tail_upload_failures should eq 0
    big_upload_failures="$(upload_cas_batch restart-big "${BIG_COUNT}" "${big_block}")"
    The variable big_upload_failures should eq 0

    dc up -d kura-us-2 >/dev/null 2>&1 || return 1
    resolve_http_node KURA_US_2 kura-us-2
    wait_for_http "${KURA_US_2_URL}/up" || return 1

    # The known applied set: all three big bodies. The threshold is not
    # reachable from big bodies plus the whole tail minus one big, so hitting
    # it proves every big applied. The throttled tail (~6s minimum on the
    # wire) leaves a wide window for the kill to land before the pass
    # completes.
    capture_into pre_restart_applied \
      wait_for_metric_ge "${KURA_US_2_URL}" kura_backfill_applied_bytes_total "" \
      "${ALL_BIGS_APPLIED_BYTES}" 600 0.2 || return 1
    The variable pre_restart_applied should not eq ''

    dc kill kura-us-2 >/dev/null 2>&1 || return 1
    dc up -d kura-us-2 >/dev/null 2>&1 || return 1
    resolve_http_node KURA_US_2 kura-us-2
    wait_for_http "${KURA_US_2_URL}/up" || return 1

    capture_into rollout_after \
      wait_for_contains "${KURA_US_2_URL}/status/rollout" \
      '"backfill_initial_cycle":"complete"' 90 2 || return 1
    The variable rollout_after should include '"backfill_initial_cycle":"complete"'

    # Fresh process, fresh counters: everything counted below is the re-walk.
    rewalk_listing_pages="$(metric_sum "${KURA_US_2_URL}" kura_backfill_listing_pages_total)"
    rewalk_applied_bytes="$(metric_sum "${KURA_US_2_URL}" kura_backfill_applied_bytes_total)"
    rewalk_present_skips="$(metric_sum "${KURA_US_2_URL}" kura_backfill_listed_tuples_total 'decision="present"')"

    # The re-walk re-lists (no watermark was written before the kill) ...
    rewalk_relisted="$((rewalk_listing_pages >= 1 ? 1 : 0))"
    The variable rewalk_relisted should eq 1
    # ... its bodies-route bytes are bounded by the known-unapplied tail plus
    # frame slack — strictly less than a single big body, so any body applied
    # before the restart being fetched again fails this bound ...
    rewalk_bytes_bounded="$((rewalk_applied_bytes <= REWALK_BODIES_BYTES_BOUND ? 1 : 0))"
    The variable rewalk_bytes_bounded should eq 1
    # ... and every big body applied before the restart resolves as already
    # present at listing time (never claimed, never requested again).
    rewalk_bigs_present_skipped="$((rewalk_present_skips >= BIG_COUNT ? 1 : 0))"
    The variable rewalk_bigs_present_skipped should eq 1

    big_mismatches="$(count_cas_status_mismatches "${KURA_US_2_URL}" restart-big "${BIG_COUNT}" 200)"
    The variable big_mismatches should eq 0
    tail_mismatches="$(count_cas_status_mismatches "${KURA_US_2_URL}" restart-tail "${TAIL_COUNT}" 200)"
    The variable tail_mismatches should eq 0
  End

  It 'completes a pass when listed entries vanish before their bodies are fetched'
    small_block="${SUITE_TMP_DIR}/small.bin"
    filler_block="${SUITE_TMP_DIR}/filler.bin"
    dd if=/dev/urandom of="${small_block}" bs=262144 count=1 2>/dev/null
    dd if=/dev/urandom of="${filler_block}" bs=1048576 count=16 2>/dev/null

    # The doomed and surviving entries are written first (older); the two
    # 16 MiB fillers are written last (newest), so the throttled walk spends
    # ~16s fetching them while the older bodies wait claimed in the queue —
    # the window in which the source-side delete lands between the listing
    # and bodies phases.
    gone_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/gone-1?tenant_id=acme&namespace_id=doomed" \
      -H "content-type: application/octet-stream" \
      --data-binary "@${small_block}")"
    The variable gone_status should eq 204
    keep_upload_failures=0
    for index in $(seq 1 8); do
      status="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/cas/keep-${index}?tenant_id=acme&namespace_id=ios" \
        -H "content-type: application/octet-stream" \
        --data-binary "@${small_block}")"
      if [ "$status" != 204 ]; then
        keep_upload_failures=$((keep_upload_failures + 1))
      fi
    done
    The variable keep_upload_failures should eq 0
    filler_upload_failures=0
    for index in $(seq 1 2); do
      status="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/cas/filler-${index}?tenant_id=acme&namespace_id=ios" \
        -H "content-type: application/octet-stream" \
        --data-binary "@${filler_block}")"
      if [ "$status" != 204 ]; then
        filler_upload_failures=$((filler_upload_failures + 1))
      fi
    done
    The variable filler_upload_failures should eq 0

    dc up -d kura-us-2 >/dev/null 2>&1 || return 1
    resolve_http_node KURA_US_2 kura-us-2
    wait_for_http "${KURA_US_2_URL}/up" || return 1

    # Wait for the listing phase to have claimed every tuple (fillers + keep +
    # doomed), then delete the doomed namespace on the source while the
    # fillers are still on the wire.
    capture_into claimed_tuples \
      wait_for_metric_ge "${KURA_US_2_URL}" kura_backfill_listed_tuples_total \
      'decision="claimed"' 11 300 0.2 || return 1
    The variable claimed_tuples should not eq ''

    delete_status="$(status_only -X DELETE \
      "${KURA_US_URL}/api/cache/clean?tenant_id=acme&namespace_id=doomed")"
    The variable delete_status should eq 204

    capture_into rollout_settled \
      wait_for_contains "${KURA_US_2_URL}/status/rollout" \
      '"backfill_initial_cycle":"complete"' 90 2 || return 1
    The variable rollout_settled should include '"backfill_initial_cycle":"complete"'

    # The vanished bodies came back as absent frames and did not fail the
    # batch or the pass (R13).
    absent_bodies="$(metric_sum "${KURA_US_2_URL}" kura_backfill_bodies_total 'outcome="absent"')"
    absent_seen="$((absent_bodies >= 1 ? 1 : 0))"
    The variable absent_seen should eq 1

    # Recency spot-check after completion: every surviving recent entry is
    # readable, and the deleted namespace stays deleted.
    keep_mismatches="$(count_cas_status_mismatches "${KURA_US_2_URL}" keep 8 200)"
    The variable keep_mismatches should eq 0
    capture_into gone_read_status \
      wait_for_status "${KURA_US_2_URL}/api/cache/cas/gone-1?tenant_id=acme&namespace_id=doomed" 404 30 2 || return 1
    The variable gone_read_status should eq 404
  End
End

Describe 'backfill throughput sanity'
  Include spec/e2e/support.sh

  THROUGHPUT_ENTRY_COUNT=128
  THROUGHPUT_ENTRY_BYTES=524288

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.discovery.yml"
      -f "${PROJECT_ROOT}/spec/e2e/docker-compose.backfill.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-backfill-throughput
    ephemeral_ports KURA_US_PORT KURA_US_2_PORT TEMPO_PORT OTLP_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    if [ "${KURA_E2E_SKIP_BUILD:-0}" != "1" ]; then
      dc build kura-us kura-us-2 >/dev/null 2>&1
    fi
    dc up -d kura-us >/dev/null 2>&1
    resolve_http_node KURA_US kura-us
    wait_for_http "${KURA_US_URL}/up" || return 1

    entry_block="${SUITE_TMP_DIR}/entry.bin"
    dd if=/dev/urandom of="${entry_block}" bs="${THROUGHPUT_ENTRY_BYTES}" count=1 2>/dev/null
    local index status
    for index in $(seq 1 "${THROUGHPUT_ENTRY_COUNT}"); do
      status="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/cas/tp-${index}?tenant_id=acme&namespace_id=ios" \
        -H "content-type: application/octet-stream" \
        --data-binary "@${entry_block}")"
      [ "$status" = 204 ] || return 1
    done
    local kv_status
    for index in $(seq 1 16); do
      kv_status="$(status_only -X PUT \
        "${KURA_US_URL}/api/cache/keyvalue?tenant_id=acme&namespace_id=ios" \
        -H "content-type: application/json" \
        -d "{\"cas_id\":\"tp-kv-${index}\",\"entries\":[{\"value\":\"throughput-${index}\"}]}")"
      [ "$kv_status" = 204 ] || return 1
    done
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  # Measured, not hard-asserted: the rate below feeds the deferred
  # KURA_BACKFILL_BATCH_BYTES default (plan: "measure and log"). The floor
  # only catches order-of-magnitude regressions — an unthrottled local
  # transfer runs far above it, and CI runner variance must not flake this.
  measure_backfill_throughput() {
    local started elapsed applied_bytes rate sample_status
    started=$SECONDS
    dc up -d kura-us-2 >/dev/null 2>&1 || { printf 'failed to start kura-us-2\n'; return 1; }
    resolve_http_node KURA_US_2 kura-us-2
    wait_for_http "${KURA_US_2_URL}/up" || return 1
    wait_for_contains "${KURA_US_2_URL}/status/rollout" \
      '"backfill_initial_cycle":"complete"' 120 1 >/dev/null || return 1
    elapsed=$((SECONDS - started))
    if [ "$elapsed" -lt 1 ]; then
      elapsed=1
    fi
    applied_bytes="$(metric_sum "${KURA_US_2_URL}" kura_backfill_applied_bytes_total)"
    rate=$((applied_bytes / elapsed))
    printf 'backfill-throughput applied_bytes=%s elapsed_s=%s rate_bytes_per_s=%s\n' \
      "$applied_bytes" "$elapsed" "$rate"
    if [ "$rate" -lt 1048576 ]; then
      printf 'measured backfill rate %s B/s is below the 1 MiB/s floor\n' "$rate"
      return 1
    fi
    sample_status="$(status_only "${KURA_US_2_URL}/api/cache/cas/tp-1?tenant_id=acme&namespace_id=ios")"
    if [ "$sample_status" != 200 ]; then
      printf 'expected tp-1 present after convergence, got status %s\n' "$sample_status"
      return 1
    fi
    kv_body="$(curl -fsS "${KURA_US_2_URL}/api/cache/keyvalue/tp-kv-1?tenant_id=acme&namespace_id=ios" 2>/dev/null || true)"
    if [[ "$kv_body" != *'throughput-1'* ]]; then
      printf 'expected tp-kv-1 present after convergence, got [%s]\n' "$kv_body"
      return 1
    fi
  }

  It 'converges a cold join above the generous floor and logs the measured rate'
    When call measure_backfill_throughput
    The status should be success
    The output should include 'backfill-throughput'
  End
End

Describe 'backfill capacity completion with an undersized ring'
  Include spec/e2e/support.sh

  # The #12047 geometry: segments seal at the compiled 512 MiB ceiling and
  # KURA_CAS_CAPACITY_BYTES=1 clamps the cold node's ring to the 5-segment
  # legacy floor, so 260 MiB module artifacts (each sealing its own segment,
  # since two no longer fit under the ceiling) make a 7-artifact dataset
  # exceed the newest ring-worth of ~5. Anything smaller cannot produce an
  # undersized ring, which is why this suite is opt-in.
  CAPACITY_MODULE_COUNT=7
  CAPACITY_PART_BYTES=10485760
  CAPACITY_PARTS_PER_MODULE=26

  capacity_module_query() {
    printf 'tenant_id=default&namespace_id=ios&hash=cap-mod-%s&name=Cap.framework&cache_category=builds' "$1"
  }

  setup_suite() {
    if [ "${KURA_E2E_BACKFILL_CAPACITY:-0}" != "1" ]; then
      return 0
    fi
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.discovery.yml"
      -f "${PROJECT_ROOT}/spec/e2e/docker-compose.backfill.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-backfill-capacity
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_US_2_PORT TEMPO_PORT OTLP_PORT
    # 32 MiB/s per source keeps the join slow enough that the ready-at-X%
    # latch is observable while the initial cycle is still pending, without
    # stretching the multi-GiB suite past CI budgets.
    suite_env KURA_E2E_REPLICATION_BW_BYTES_PER_SECOND 33554432
    suite_env KURA_E2E_COLD_CAS_CAPACITY_BYTES 1

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    if [ "${KURA_E2E_SKIP_BUILD:-0}" != "1" ]; then
      dc build kura-us kura-eu kura-us-2 >/dev/null 2>&1
    fi
    dc up -d kura-us >/dev/null 2>&1
    resolve_http_node KURA_US kura-us
    wait_for_http "${KURA_US_URL}/up" || return 1
    capture_into us_up wait_for_contains "${KURA_US_URL}/up" '"ring_members":1' || return 1
    [[ "${us_up}" == *'"ring_members":1'* ]]
  }

  teardown_suite() {
    if [ -z "${COMPOSE_ENV_FILE:-}" ]; then
      return 0
    fi
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  upload_capacity_module() {
    local index="$1"
    local nsq start_response upload_id part status parts_json
    nsq="$(capacity_module_query "$index")"
    start_response="$(curl -fsS -X POST "${KURA_US_URL}/api/cache/module/start?${nsq}")" || return 1
    upload_id="$(extract_upload_id "${start_response}")"
    [ -n "$upload_id" ] || return 1
    for part in $(seq 1 "${CAPACITY_PARTS_PER_MODULE}"); do
      status="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/module/part?upload_id=${upload_id}&part_number=${part}" \
        -H "content-type: application/octet-stream" \
        --data-binary "@${CAPACITY_BLOCK}")"
      [ "$status" = 204 ] || return 1
    done
    parts_json="$(seq 1 "${CAPACITY_PARTS_PER_MODULE}" | paste -sd, -)"
    status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/complete?upload_id=${upload_id}" \
      -H "content-type: application/json" \
      -d "{\"parts\":[${parts_json}]}")"
    [ "$status" = 204 ]
  }

  # The whole scenario lives in one function invoked via `When call`: a
  # skipped example must not execute any of it (plain shell lines in an It
  # body still run under Skip), and the summary line doubles as the logged
  # measurement.
  run_capacity_check() {
    local index join_started ready_seen ready_elapsed rollout_at_ready
    local rollout_settled total_elapsed evicted_artifacts present_count retained

    CAPACITY_BLOCK="${SUITE_TMP_DIR}/capacity-block.bin"
    dd if=/dev/urandom of="${CAPACITY_BLOCK}" bs="${CAPACITY_PART_BYTES}" count=1 2>/dev/null

    for index in $(seq 1 "${CAPACITY_MODULE_COUNT}"); do
      if ! upload_capacity_module "$index"; then
        printf 'upload of module %s failed\n' "$index"
        return 1
      fi
    done

    # Both sources must hold the full dataset before the cold node joins —
    # that is the two-source half of the #12047 shape. The second source is
    # seeded through a cold backfill join rather than write-time replication:
    # the replication client's fixed request timeout starves 260 MiB bodies
    # under the throttled limiter (the tuist/tuist#11297 shape the
    # large-artifact suite dodges by disabling the limiter), while the
    # backfill per-artifact path uses idle-based timeouts and transfers them
    # fine at the shaped rate.
    dc up -d kura-eu >/dev/null 2>&1 || { printf 'failed to start kura-eu\n'; return 1; }
    resolve_http_node KURA_EU kura-eu
    wait_for_http "${KURA_EU_URL}/up" || return 1
    wait_for_contains "${KURA_EU_URL}/status/rollout" \
      '"backfill_initial_cycle":"complete"' 150 2 >/dev/null || {
      printf 'second source never completed its seeding backfill\n'
      return 1
    }
    for index in $(seq 1 "${CAPACITY_MODULE_COUNT}"); do
      wait_for_head_status \
        "${KURA_EU_URL}/api/cache/module/x?$(capacity_module_query "$index")" 204 60 2 >/dev/null || {
        printf 'module %s never reached the second source\n' "$index"
        return 1
      }
    done

    join_started=$SECONDS
    dc up -d kura-us-2 >/dev/null 2>&1 || { printf 'failed to start kura-us-2\n'; return 1; }
    resolve_http_node KURA_US_2 kura-us-2
    wait_for_http "${KURA_US_2_URL}/up" || return 1

    # Ready-at-X%: readiness must latch on ring fullness while the initial
    # cycle is still running, bounded well below the full transfer time.
    ready_seen=0
    ready_elapsed=0
    rollout_at_ready=""
    for _ in $(seq 1 480); do
      if [ "$(status_only "${KURA_US_2_URL}/ready" 2>/dev/null || true)" = 200 ]; then
        ready_seen=1
        ready_elapsed=$((SECONDS - join_started))
        rollout_at_ready="$(curl -fsS "${KURA_US_2_URL}/status/rollout" 2>/dev/null || true)"
        break
      fi
      sleep 0.5
    done
    if [ "$ready_seen" != 1 ]; then
      printf 'cold node never became ready during the backfill\n'
      return 1
    fi
    if [[ "$rollout_at_ready" != *'"backfill_initial_cycle":"pending"'* ]]; then
      printf 'expected readiness to latch while the cycle was pending, rollout was: %s\n' "$rollout_at_ready"
      return 1
    fi

    rollout_settled="$(wait_for_contains "${KURA_US_2_URL}/status/rollout" \
      '"backfill_initial_cycle":"complete"' 240 2)" || return 1
    total_elapsed=$((SECONDS - join_started))

    # The #12047 success signature: a capacity-completing backfill evicts
    # (almost) nothing — the marginal trade stops segmented fetches instead of
    # churning the ring. The small allowance covers a single boundary
    # rotation; the incident signature was millions.
    evicted_artifacts="$(metric_sum "${KURA_US_2_URL}" kura_segment_evicted_artifacts_total)"
    if [ "${evicted_artifacts:-0}" -gt 3 ]; then
      printf 'eviction thrash: %s artifacts evicted during a capacity-completing backfill\n' "$evicted_artifacts"
      return 1
    fi

    # Newest ring-worth retained, modulo the plan's accepted mixed-depth
    # boundary churn: each concurrent pass may overshoot the capacity boundary
    # by its one in-flight fetch, and on this deliberately coarse geometry
    # (1 artifact ≈ 1 segment) each overshoot rotates a whole segment holding
    # the newest applied artifact. The honest contract is therefore: exactly a
    # ring-worth (5 segments → 5 artifacts) is retained — which is itself the
    # undersized-ring proof, since all 7 present would mean the ring never
    # filled — and the interior of the newest band is always among them.
    present_count=0
    retained=""
    for index in $(seq 1 "${CAPACITY_MODULE_COUNT}"); do
      if [ "$(status_only -I "${KURA_US_2_URL}/api/cache/module/x?$(capacity_module_query "$index")")" = 204 ]; then
        present_count=$((present_count + 1))
        retained="${retained} cap-mod-${index}"
      fi
    done
    if [ "$present_count" != 5 ]; then
      printf 'expected exactly a ring-worth (5) retained, got %s (%s)\n' "$present_count" "$retained"
      return 1
    fi
    for index in 5 4 3; do
      if [[ "$retained" != *" cap-mod-${index}"* ]]; then
        printf 'interior module %s of the newest band missing; retained:%s\n' "$index" "$retained"
        return 1
      fi
    done

    printf 'backfill-capacity ready_after_s=%s complete_after_s=%s evicted_artifacts=%s retained=%s\n' \
      "$ready_elapsed" "$total_elapsed" "$evicted_artifacts" "$retained"
  }

  It 'backfills the newest ring-worth from two sources without eviction thrash'
    Skip if "set KURA_E2E_BACKFILL_CAPACITY=1 to run (moves several GiB, ~10 min)" \
      [ "${KURA_E2E_BACKFILL_CAPACITY:-0}" != "1" ]

    When call run_capacity_check
    The status should be success
    The output should include 'backfill-capacity'
  End
End
