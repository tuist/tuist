# shellcheck shell=bash

Describe 'memory pressure resilience'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/spec/e2e/docker-compose.memory-pressure.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-memory-pressure
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT \
      KURA_US_GRPC_PORT KURA_EU_GRPC_PORT KURA_AP_GRPC_PORT
    suite_env KURA_E2E_DOCKER_MEMORY_LIMIT 512m
    suite_env KURA_E2E_MEMORY_SOFT_LIMIT_BYTES $((256 * 1024 * 1024))
    suite_env KURA_E2E_MEMORY_HARD_LIMIT_BYTES $((320 * 1024 * 1024))
    suite_env KURA_E2E_MANIFEST_CACHE_MAX_BYTES $((16 * 1024 * 1024))
    suite_env KURA_E2E_SEGMENT_HANDLE_CACHE_SIZE 8
    suite_env KURA_E2E_METADATA_STORE_READ_CACHE_BYTES $((16 * 1024 * 1024))
    suite_env KURA_E2E_METADATA_STORE_WRITE_BUFFER_POOL_BYTES $((16 * 1024 * 1024))
    suite_env KURA_E2E_METADATA_STORE_WRITE_BUFFER_BYTES $((8 * 1024 * 1024))

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us kura-eu kura-ap || return 1

    resolve_http_node KURA_US kura-us
    resolve_http_node KURA_EU kura-eu
    resolve_http_node KURA_AP kura-ap

    wait_for_http "${KURA_US_URL}/up"
    wait_for_http "${KURA_EU_URL}/up"
    wait_for_http "${KURA_AP_URL}/up"
    capture_into us_up wait_for_contains "${KURA_US_URL}/up" '"ring_members":3' || return 1
    capture_into eu_up wait_for_contains "${KURA_EU_URL}/up" '"ring_members":3' || return 1
    capture_into ap_up wait_for_contains "${KURA_AP_URL}/up" '"ring_members":3' || return 1
    [[ "${us_up}" == *'"ring_members":3'* ]]
    [[ "${eu_up}" == *'"ring_members":3'* ]]
    [[ "${ap_up}" == *'"ring_members":3'* ]]
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  It 'stays healthy under sustained public api traffic with tight memory limits'
    artifact_id="artifact-$(new_marker)"
    cas_id="cas-$(new_marker)"
    artifact_path="${SUITE_TMP_DIR}/${artifact_id}.bin"
    cas_url_us="${KURA_US_URL}/api/cache/cas/${artifact_id}?tenant_id=acme&namespace_id=ios"
    cas_url_eu="${KURA_EU_URL}/api/cache/cas/${artifact_id}?tenant_id=acme&namespace_id=ios"
    cas_url_ap="${KURA_AP_URL}/api/cache/cas/${artifact_id}?tenant_id=acme&namespace_id=ios"
    keyvalue_url_us="${KURA_US_URL}/api/cache/keyvalue/${cas_id}?tenant_id=acme&namespace_id=ios"
    keyvalue_url_eu="${KURA_EU_URL}/api/cache/keyvalue/${cas_id}?tenant_id=acme&namespace_id=ios"
    keyvalue_url_ap="${KURA_AP_URL}/api/cache/keyvalue/${cas_id}?tenant_id=acme&namespace_id=ios"

    python3 - <<'PY' >"${artifact_path}"
import sys

chunk = b"kura-memory-pressure-traffic"
size = 4 * 1024 * 1024
repetitions = (size + len(chunk) - 1) // len(chunk)
sys.stdout.buffer.write((chunk * repetitions)[:size])
PY

    artifact_status="$(status_only -X POST \
      "${cas_url_us}" \
      -H "content-type: application/octet-stream" \
      --data-binary "@${artifact_path}")"
    The variable artifact_status should eq 204

    keyvalue_status="$(status_only -X PUT \
      "${KURA_US_URL}/api/cache/keyvalue?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/json" \
      -d "{\"cas_id\":\"${cas_id}\",\"entries\":[{\"value\":\"load\"},{\"value\":\"probe\"}]}")"
    The variable keyvalue_status should eq 204

    capture_into eu_cas_status wait_for_status "${cas_url_eu}" 200 || return 1
    capture_into ap_cas_status wait_for_status "${cas_url_ap}" 200 || return 1
    The variable eu_cas_status should eq 200
    The variable ap_cas_status should eq 200

    capture_into eu_keyvalue wait_for_contains "${keyvalue_url_eu}" '"load"' || return 1
    capture_into ap_keyvalue wait_for_contains "${keyvalue_url_ap}" '"probe"' || return 1
    The variable eu_keyvalue should include '"load"'
    The variable ap_keyvalue should include '"probe"'

    run_parallel_http_gets "${cas_url_us}" 6 12 &
    cas_us_pid=$!
    run_parallel_http_gets "${cas_url_eu}" 6 12 &
    cas_eu_pid=$!
    run_parallel_http_gets "${cas_url_ap}" 6 12 &
    cas_ap_pid=$!
    run_parallel_http_gets "${keyvalue_url_us}" 6 40 &
    keyvalue_us_pid=$!
    run_parallel_http_gets "${keyvalue_url_eu}" 6 40 &
    keyvalue_eu_pid=$!
    run_parallel_http_gets "${keyvalue_url_ap}" 6 40 &
    keyvalue_ap_pid=$!

    wait "${cas_us_pid}" || return 1
    wait "${cas_eu_pid}" || return 1
    wait "${cas_ap_pid}" || return 1
    wait "${keyvalue_us_pid}" || return 1
    wait "${keyvalue_eu_pid}" || return 1
    wait "${keyvalue_ap_pid}" || return 1

    capture_into us_after wait_for_contains "${KURA_US_URL}/up" '"ring_members":3' || return 1
    capture_into eu_after wait_for_contains "${KURA_EU_URL}/up" '"ring_members":3' || return 1
    capture_into ap_after wait_for_contains "${KURA_AP_URL}/up" '"ring_members":3' || return 1
    The variable us_after should include '"ring_members":3'
    The variable eu_after should include '"ring_members":3'
    The variable ap_after should include '"ring_members":3'

    us_status="$(container_status kura-us)"
    eu_status="$(container_status kura-eu)"
    ap_status="$(container_status kura-ap)"
    The variable us_status should eq running
    The variable eu_status should eq running
    The variable ap_status should eq running

    us_restarts="$(container_restart_count kura-us)"
    eu_restarts="$(container_restart_count kura-eu)"
    ap_restarts="$(container_restart_count kura-ap)"
    The variable us_restarts should eq 0
    The variable eu_restarts should eq 0
    The variable ap_restarts should eq 0

    us_oom_killed="$(container_oom_killed kura-us)"
    eu_oom_killed="$(container_oom_killed kura-eu)"
    ap_oom_killed="$(container_oom_killed kura-ap)"
    The variable us_oom_killed should eq false
    The variable eu_oom_killed should eq false
    The variable ap_oom_killed should eq false
  End
End
