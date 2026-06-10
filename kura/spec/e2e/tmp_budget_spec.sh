# shellcheck shell=bash

Describe 'temporary staging budget'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-tmp-budget
    ephemeral_ports KURA_US_PORT KURA_US_GRPC_PORT
    suite_env KURA_E2E_TMP_DIR_MAX_BYTES 1048576

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us || return 1

    resolve_http_node KURA_US kura-us
    wait_for_http "${KURA_US_URL}/up"
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'resolve_http_node KURA_US kura-us'
  AfterAll 'teardown_suite'

  It 'returns backpressure instead of relying on the mounted volume limit'
    artifact_path="${SUITE_TMP_DIR}/artifact.bin"
    python3 - <<'PY' >"${artifact_path}"
import sys

sys.stdout.buffer.write(b"kura-tmp-budget")
PY

    capture_into response \
      curl -sS -X POST \
      -o "${SUITE_TMP_DIR}/response.txt" \
      -w "%{http_code}" \
      "${KURA_US_URL}/api/cache/cas/tmp-budget?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "@${artifact_path}" || return 1

    The variable response should eq 503

    capture_into response_body cat "${SUITE_TMP_DIR}/response.txt" || return 1
    The variable response_body should include 'Temporary storage budget exhausted'

    capture_into up_body wait_for_contains "${KURA_US_URL}/up" '"status":"ok"' || return 1
    The variable up_body should include '"status":"ok"'

    status="$(container_status kura-us)"
    restart_count="$(container_restart_count kura-us)"
    oom_killed="$(container_oom_killed kura-us)"
    The variable status should eq running
    The variable restart_count should eq 0
    The variable oom_killed should eq false
  End
End
