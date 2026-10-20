# shellcheck shell=bash

Describe 'memory-derived multipart admission'
  Include spec/e2e/support.sh

  setup_suite() {
    setup_suite_tmpdir
    if [ -n "${KURA_MULTIPART_TEST_URL:-}" ]; then
      KURA_US_URL="${KURA_MULTIPART_TEST_URL}"
      return 0
    fi
    # Give the normal-pressure fixture ample room while retaining exactly
    # 256 MiB between watermarks. Pressure transitions have unit coverage.
    cat >"${SUITE_TMP_DIR}/admission.yml" <<'YAML'
services:
  kura-us:
    mem_limit: 2g
    environment:
      KURA_MEMORY_SOFT_LIMIT_BYTES: "1073741824"
      KURA_MEMORY_HARD_LIMIT_BYTES: "1342177280"
      KURA_METADATA_STORE_READ_CACHE_BYTES: "16777216"
      KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES: "16777216"
      KURA_METADATA_STORE_WRITE_BUFFER_BYTES: "4194304"
      KURA_PEERS: ""
      KURA_DISCOVERY_DNS_NAME: ""
YAML
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml" -f "${SUITE_TMP_DIR}/admission.yml")
    suite_env COMPOSE_PROJECT_NAME kura-multipart-admission
    ephemeral_ports KURA_US_PORT
    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us || return 1
    resolve_http_node KURA_US kura-us
    wait_for_node_ready "${KURA_US_URL}"
  }

  teardown_suite() {
    if [ -n "${KURA_MULTIPART_TEST_URL:-}" ]; then
      rm -rf "${SUITE_TMP_DIR:?}"
    else
      compose_teardown
    fi
  }

  resolve_suite_node() {
    if [ -n "${KURA_MULTIPART_TEST_URL:-}" ]; then
      KURA_US_URL="${KURA_MULTIPART_TEST_URL}"
    else
      resolve_http_node KURA_US kura-us
    fi
  }

  metric_value() {
    curl -fsS "${KURA_US_URL}/metrics" | awk -v name="$1" '$1 == name { print $2 }'
  }

  wait_metric_value() {
    for _ in $(seq 1 100); do
      value="$(metric_value "$1")"
      [ "${value}" = "$2" ] && return 0
      sleep 0.1
    done
    return 1
  }

  BeforeAll 'setup_suite'
  Before 'resolve_suite_node'
  AfterAll 'teardown_suite'

  It 'admits more than 128 sessions and sheds at its memory-derived limit'
    wait_metric_value kura_memory_pressure_state 0 || return 1
    wait_metric_value kura_multipart_upload_capacity 256 || return 1

    capture_into first_start curl -fsS -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=first&name=Module&cache_category=builds" || return 1
    first_id="$(extract_upload_id "${first_start}")"
    first_part="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/part?upload_id=${first_id}&part_number=1" \
      --data-binary 'payload')"
    The variable first_part should eq 204
    admitted=1
    for index in $(seq 2 256); do
      response="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=burst-${index}&name=Module&cache_category=builds")"
      if [ "${response}" != 200 ]; then
        break
      fi
      admitted=$((admitted + 1))
    done
    The variable admitted should eq 256
    saturated="$(curl -sS -o /dev/null -w '%{http_code} %{time_total}' -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=saturated&name=Module&cache_category=builds")"
    bounded_timeout="$(printf '%s' "${saturated}" | awk '{print ($1 == 429 && $2 >= 0.9 && $2 < 5) ? "yes" : "no"}')"
    The variable bounded_timeout should eq yes

    curl -sS -o "${SUITE_TMP_DIR}/waiting.json" -w '%{http_code}' -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=waiting&name=Module&cache_category=builds" \
      >"${SUITE_TMP_DIR}/waiting.status" &
    waiting_pid=$!
    # Exact gauge matching cannot mistake 20 queued requests for 2.
    for _ in $(seq 1 50); do
      queued="$(metric_value kura_multipart_upload_waiters)"
      [ "${queued}" = 1 ] && break
      sleep 0.01
    done
    The variable queued should eq 1
    completed="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/complete?upload_id=${first_id}" \
      -H 'content-type: application/json' -d '{"parts":[1]}')"
    The variable completed should eq 204
    wait "${waiting_pid}"
    waiting_status="$(cat "${SUITE_TMP_DIR}/waiting.status")"
    The variable waiting_status should eq 200
    waiting_id="$(extract_upload_id "$(cat "${SUITE_TMP_DIR}/waiting.json")")"
    The variable waiting_id should be present

    wait_metric_value kura_multipart_uploads 256 || return 1
    wait_metric_value kura_multipart_upload_capacity 256 || return 1
    wait_metric_value kura_multipart_upload_waiters 0 || return 1
    wait_metric_value 'kura_multipart_upload_admissions_total_total{outcome="timeout"}' 1 || return 1
    wait_metric_value 'kura_multipart_upload_admissions_total_total{outcome="waited"}' 1 || return 1
  End
End
