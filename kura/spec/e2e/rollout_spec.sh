# shellcheck shell=bash

Describe 'warm rollout lifecycle'
  Include spec/e2e/support.sh

  setup_suite() {
    export COMPOSE_PROJECT_NAME="kura-rollout"
    export KURA_US_PORT=4601
    export TEMPO_PORT=3315
    export OTLP_PORT=4430
    export KURA_US_URL="http://localhost:${KURA_US_PORT}"

    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.discovery.yml"
    )
    setup_suite_tmpdir

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc build kura-us >/dev/null 2>&1
  }

  reset_cluster() {
    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc up -d kura-us >/dev/null 2>&1
    wait_for_http "${KURA_US_URL}/up" || return 1
    wait_for_http "${KURA_US_URL}/ready" || return 1
    capture_into ready_body wait_for_contains "${KURA_US_URL}/ready" '"state":"serving"' || return 1
    [[ "${ready_body}" == *'"ready":true'* ]]
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  Before 'reset_cluster'
  AfterAll 'teardown_suite'

  It 'drains public traffic before replacement and comes back ready on the same PVC'
    artifact_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/warm-rollout-artifact?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "warm-rollout-binary")"
    The variable artifact_status should eq 204

    dc exec -T kura-us sh -lc 'KURA_PID="$(tr " " "\n" </proc/1/task/1/children | head -n1)" && [ -n "$KURA_PID" ] && kill -USR1 "$KURA_PID"' >/dev/null 2>&1 || return 1

    capture_into ready_status wait_for_status "${KURA_US_URL}/ready" 503 || return 1
    The variable ready_status should eq 503

    capture_into ready_body curl -sS "${KURA_US_URL}/ready" || return 1
    The variable ready_body should include '"state":"draining"'
    The variable ready_body should include '"ready":false'
    The variable ready_body should include '"draining":true'

    liveness_status="$(status_only "${KURA_US_URL}/up")"
    The variable liveness_status should eq 200

    capture_into draining_headers \
      sh -lc "curl -sS --http1.1 -D - -o /dev/null '${KURA_US_URL}/api/cache/cas/warm-rollout-artifact?tenant_id=acme&namespace_id=ios' | tr '[:upper:]' '[:lower:]'" || return 1
    The variable draining_headers should include 'http/1.1 503 service unavailable'
    The variable draining_headers should include 'connection: close'

    capture_into internal_status \
      dc exec -T kura-us curl -fsS http://localhost:7443/_internal/status || return 1
    The variable internal_status should include '"node_url":"http://kura-us.kura.internal:7443"'

    dc stop kura-us >/dev/null 2>&1 || return 1
    dc rm -f kura-us >/dev/null 2>&1 || return 1
    dc up -d kura-us >/dev/null 2>&1 || return 1

    wait_for_http "${KURA_US_URL}/up" || return 1
    wait_for_http "${KURA_US_URL}/ready" || return 1
    capture_into ready_after wait_for_contains "${KURA_US_URL}/ready" '"state":"serving"' || return 1
    The variable ready_after should include '"ready":true'

    capture_into artifact_after \
      wait_for_contains \
      "${KURA_US_URL}/api/cache/cas/warm-rollout-artifact?tenant_id=acme&namespace_id=ios" \
      'warm-rollout-binary' || return 1
    The variable artifact_after should eq 'warm-rollout-binary'
  End

  It 'refuses a second writer against the same PVC'
    capture_into second_writer_output \
      dc exec -T kura-us sh -lc '
        rm -rf /tmp/kura-locktest &&
        mkdir -p /tmp/kura-locktest &&
        KURA_PORT=4010 \
        KURA_GRPC_PORT=50110 \
        KURA_INTERNAL_PORT=7444 \
        KURA_NODE_URL=http://lock-test.kura.internal:7444 \
        KURA_PEERS=http://lock-test.kura.internal:7444 \
        KURA_DATA_DIR=/var/cache/kura \
        KURA_TMP_DIR=/tmp/kura-locktest \
        /usr/local/bin/kura >/tmp/second-writer.log 2>&1
        status=$?
        cat /tmp/second-writer.log
        printf "\nexit_status=%s\n" "$status"
      ' || return 1
    The variable second_writer_output should include 'failed to acquire writer lock'
    The variable second_writer_output should include 'exit_status=1'
  End
End
