# shellcheck shell=bash

Describe 'eventual-consistency fault recovery'
  Include spec/e2e/support.sh

  setup_suite() {
    export COMPOSE_PROJECT_NAME="kura-faults"
    export KURA_US_PORT=4501
    export KURA_US_2_PORT=4502
    export TEMPO_PORT=3305
    export OTLP_PORT=4422
    export KURA_US_URL="http://localhost:${KURA_US_PORT}"
    export KURA_US_2_URL="http://localhost:${KURA_US_2_PORT}"

    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.discovery.yml"
    )
    setup_suite_tmpdir

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc build kura-us kura-us-2 >/dev/null 2>&1
  }

  reset_cluster() {
    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc up -d kura-us >/dev/null 2>&1
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

  It 'does not resurrect deleted namespace state during bootstrap'
    keyvalue_status="$(status_only -X PUT \
      "${KURA_US_URL}/api/cache/keyvalue?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/json" \
      -d '{"cas_id":"cas-delete","entries":[{"value":"stale-after-delete"}]}')"
    The variable keyvalue_status should eq 204

    artifact_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/artifact-delete?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "stale-binary")"
    The variable artifact_status should eq 204

    delete_status="$(status_only -X DELETE \
      "${KURA_US_URL}/api/cache/clean?tenant_id=acme&namespace_id=ios")"
    The variable delete_status should eq 204

    dc up -d kura-us-2 >/dev/null 2>&1 || return 1
    wait_for_http "${KURA_US_2_URL}/up" || return 1
    capture_into us_ring wait_for_contains "${KURA_US_URL}/up" '"ring_members":2' || return 1
    capture_into us2_ring wait_for_contains "${KURA_US_2_URL}/up" '"ring_members":2' || return 1
    The variable us_ring should include '"ring_members":2'
    The variable us2_ring should include '"ring_members":2'

    keyvalue_read_status="$(status_only \
      "${KURA_US_2_URL}/api/cache/keyvalue/cas-delete?tenant_id=acme&namespace_id=ios")"
    The variable keyvalue_read_status should eq 404

    artifact_read_status="$(status_only \
      "${KURA_US_2_URL}/api/cache/cas/artifact-delete?tenant_id=acme&namespace_id=ios")"
    The variable artifact_read_status should eq 404
  End

  It 'converges after a node rejoins and queued retries race with bootstrap'
    dc up -d kura-us-2 >/dev/null 2>&1 || return 1
    wait_for_http "${KURA_US_2_URL}/up" || return 1
    capture_into us_ring wait_for_contains "${KURA_US_URL}/up" '"ring_members":2' || return 1
    capture_into us2_ring wait_for_contains "${KURA_US_2_URL}/up" '"ring_members":2' || return 1
    The variable us_ring should include '"ring_members":2'
    The variable us2_ring should include '"ring_members":2'

    dc stop kura-us-2 >/dev/null 2>&1 || return 1

    keyvalue_status="$(status_only -X PUT \
      "${KURA_US_URL}/api/cache/keyvalue?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/json" \
      -d '{"cas_id":"cas-rejoin","entries":[{"value":"from-outage"},{"value":"from-retry"}]}')"
    The variable keyvalue_status should eq 204

    artifact_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/artifact-rejoin?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "rejoin-binary")"
    The variable artifact_status should eq 204

    dc up -d kura-us-2 >/dev/null 2>&1 || return 1
    wait_for_http "${KURA_US_2_URL}/up" || return 1
    capture_into us_ring_after wait_for_contains "${KURA_US_URL}/up" '"ring_members":2' || return 1
    capture_into us2_ring_after wait_for_contains "${KURA_US_2_URL}/up" '"ring_members":2' || return 1
    The variable us_ring_after should include '"ring_members":2'
    The variable us2_ring_after should include '"ring_members":2'

    capture_into replicated_keyvalue \
      wait_for_contains \
      "${KURA_US_2_URL}/api/cache/keyvalue/cas-rejoin?tenant_id=acme&namespace_id=ios" \
      '"from-outage"' || return 1
    The variable replicated_keyvalue should include '"from-outage"'
    The variable replicated_keyvalue should include '"from-retry"'

    capture_into replicated_artifact \
      wait_for_contains \
      "${KURA_US_2_URL}/api/cache/cas/artifact-rejoin?tenant_id=acme&namespace_id=ios" \
      'rejoin-binary' || return 1
    The variable replicated_artifact should eq 'rejoin-binary'

    gradle_status="$(status_only -X PUT \
      "${KURA_US_2_URL}/api/cache/gradle/gradle-rejoin?tenant_id=acme&namespace_id=android" \
      -H "content-type: application/octet-stream" \
      --data-binary "healthy-after-rejoin")"
    The variable gradle_status should eq 201

    capture_into upstream_gradle \
      wait_for_contains \
      "${KURA_US_URL}/api/cache/gradle/gradle-rejoin?tenant_id=acme&namespace_id=android" \
      'healthy-after-rejoin' || return 1
    The variable upstream_gradle should eq 'healthy-after-rejoin'
  End
End
