# shellcheck shell=bash

Describe 'DNS discovery and bootstrap'
  Include spec/e2e/support.sh

  setup_suite() {
    export COMPOSE_PROJECT_NAME="kura-discovery"
    export KURA_US_PORT=4401
    export KURA_US_2_PORT=4402
    export TEMPO_PORT=3303
    export OTLP_PORT=4420
    export KURA_US_URL="http://localhost:${KURA_US_PORT}"
    export KURA_US_2_URL="http://localhost:${KURA_US_2_PORT}"

    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.discovery.yml"
    )
    setup_suite_tmpdir

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc build kura-us kura-us-2 >/dev/null 2>&1
    dc up -d kura-us >/dev/null 2>&1

    wait_for_http "${KURA_US_URL}/up"
    capture_into us_up wait_for_contains "${KURA_US_URL}/up" '"ring_members":1' || return 1
    [[ "${us_up}" == *'"ring_members":1'* ]]
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  It 'bootstraps and replicates a new node discovered through DNS'
    keyvalue_status="$(status_only -X PUT \
      "${KURA_US_URL}/api/cache/keyvalue?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/json" \
      -d '{"cas_id":"cas-1","entries":[{"value":"from-singleton"},{"value":"ready-for-join"}]}')"
    The variable keyvalue_status should eq 204

    artifact_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "xcode-binary")"
    The variable artifact_status should eq 204

    dc up -d kura-us-2 >/dev/null 2>&1 || return 1

    wait_for_http "${KURA_US_2_URL}/up" || return 1
    capture_into us_ring wait_for_contains "${KURA_US_URL}/up" '"ring_members":2' || return 1
    capture_into us2_ring wait_for_contains "${KURA_US_2_URL}/up" '"ring_members":2' || return 1
    The variable us_ring should include '"ring_members":2'
    The variable us2_ring should include '"ring_members":2'

    capture_into replicated_keyvalue \
      wait_for_contains \
      "${KURA_US_2_URL}/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios" \
      '"from-singleton"' || return 1
    The variable replicated_keyvalue should include '"from-singleton"'
    The variable replicated_keyvalue should include '"ready-for-join"'

    capture_into replicated_artifact \
      wait_for_contains \
      "${KURA_US_2_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      'xcode-binary' || return 1
    The variable replicated_artifact should eq 'xcode-binary'

    gradle_status="$(status_only -X PUT \
      "${KURA_US_2_URL}/api/cache/gradle/gradle-key-1?tenant_id=acme&namespace_id=android" \
      -H "content-type: application/octet-stream" \
      --data-binary "from-new-node")"
    The variable gradle_status should eq 201

    capture_into upstream_gradle \
      wait_for_contains \
      "${KURA_US_URL}/api/cache/gradle/gradle-key-1?tenant_id=acme&namespace_id=android" \
      'from-new-node' || return 1
    The variable upstream_gradle should eq 'from-new-node'
  End
End
