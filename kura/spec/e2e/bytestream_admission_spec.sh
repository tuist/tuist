# shellcheck shell=bash

Describe 'ByteStream response admission'
  Include spec/e2e/support.sh

  setup_suite() {
    setup_suite_tmpdir
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml" -f "${PROJECT_ROOT}/test/e2e/bytestream-admission/docker-compose.yml")
    suite_env COMPOSE_PROJECT_NAME "kura-bytestream-$(basename "${SUITE_TMP_DIR}" | tr '[:upper:].' '[:lower:]-')"
    ephemeral_ports KURA_US_PORT
    dc build bytestream-client >"${SUITE_TMP_DIR}/client-build.log" 2>&1 || {
      cat "${SUITE_TMP_DIR}/client-build.log"
      return 1
    }
    compose_up kura-us || return 1
    resolve_http_node KURA_US kura-us
    wait_for_node_ready "${KURA_US_URL}" || return 1
    capture_into seeded dc run --rm --no-deps \
      -e LOAD_OPERATION=write -e LOAD_REQUESTS=1 -e LOAD_CONCURRENCY=1 \
      -e LOAD_MIN_REQUEST_MS=0 bytestream-client || {
      printf '%s\n' "${seeded}"
      return 1
    }
  }

  resolve_suite_node() {
    resolve_http_node KURA_US kura-us
  }

  snapshot_resources() {
    local phase="$1" directory="${KURA_E2E_BYTESTREAM_OUTPUT_DIR}"
    curl -fsS "${KURA_US_URL}/metrics" >"${directory}/${phase}.metrics" || return 1
    dc exec -T kura-us cat /sys/fs/cgroup/cpu.stat >"${directory}/${phase}.cpu.stat" || return 1
    dc exec -T kura-us du -sk /var/cache/kura >"${directory}/${phase}.disk" || return 1
  }

  run_burst() {
    local read_pid result=0 queued=no sample=0 metrics="${SUITE_TMP_DIR}/read.metrics"
    if [ -n "${KURA_E2E_BYTESTREAM_OUTPUT_DIR:-}" ]; then
      mkdir "${KURA_E2E_BYTESTREAM_OUTPUT_DIR}" || return 1
      sleep 5
      snapshot_resources idle || return 1
    fi
    dc run --rm --no-deps --name "${COMPOSE_PROJECT_NAME}-reader" bytestream-client >"${SUITE_TMP_DIR}/read.log" 2>&1 &
    read_pid=$!
    while kill -0 "${read_pid}" 2>/dev/null; do
      if ! curl -fsS "${KURA_US_URL}/metrics" >"${metrics}"; then
        docker rm -f "${COMPOSE_PROJECT_NAME}-reader" >/dev/null 2>&1 || true
        result=1
        break
      fi
      if awk '$1 == "kura_response_stream_waiters{protocol=\"bytestream\"}" && $2 > 0 { found=1 } END { exit !found }' "${metrics}"; then
        queued=yes
      fi
      if [ -n "${KURA_E2E_BYTESTREAM_OUTPUT_DIR:-}" ]; then
        cp "${metrics}" "${KURA_E2E_BYTESTREAM_OUTPUT_DIR}/$(printf '%05d' "${sample}")-read.metrics" || result=1
      fi
      sample=$((sample + 1))
      sleep 0.1
    done
    wait "${read_pid}" || result=1
    cat "${SUITE_TMP_DIR}/read.log"
    printf 'queued=%s\n' "${queued}"
    if [ -n "${KURA_E2E_BYTESTREAM_OUTPUT_DIR:-}" ]; then
      cp "${SUITE_TMP_DIR}/read.log" "${KURA_E2E_BYTESTREAM_OUTPUT_DIR}/read.log" || return 1
      snapshot_resources completed || return 1
      for sample in $(seq 1 15); do
        sleep 1
        curl -fsS "${KURA_US_URL}/metrics" >"${KURA_E2E_BYTESTREAM_OUTPUT_DIR}/$(printf '%05d' "${sample}")-recovery.metrics" || return 1
      done
      snapshot_resources settled || return 1
    fi
    return "${result}"
  }

  teardown_suite() {
    if [ -n "${KURA_E2E_BYTESTREAM_OUTPUT_DIR:-}" ] && [ -d "${KURA_E2E_BYTESTREAM_OUTPUT_DIR}" ]; then
      dc logs --no-color kura-us >"${KURA_E2E_BYTESTREAM_OUTPUT_DIR}/server.log" 2>&1 || true
    fi
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'resolve_suite_node'
  AfterAll 'teardown_suite'

  It 'queues a burst of paced readers without rejecting or corrupting reads'
    When call run_burst
    The status should be success
    The output should include "codes=map[OK:${KURA_E2E_BYTESTREAM_REQUESTS:-128}]"
    The output should include 'queued=yes'
  End
End
