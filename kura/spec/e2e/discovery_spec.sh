# shellcheck shell=bash

Describe 'DNS discovery and bootstrap'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.discovery.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-discovery
    ephemeral_ports KURA_US_PORT KURA_US_2_PORT TEMPO_PORT OTLP_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc build kura-us kura-us-2 >/dev/null 2>&1
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
    resolve_http_node KURA_US_2 kura-us-2

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

# Flag-on twin of the scenario above: the same new-node convergence must hold
# when the mesh runs the backfill walker (KURA_BACKFILL_ENABLED) instead of
# legacy bootstrap. Both walkers ship in the Release AB binary and both must
# keep working until Release C deletes the legacy one, so the flag-off
# Describe above stays untouched.
Describe 'DNS discovery and backfill catch-up (flag-on)'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.discovery.yml"
      -f "${PROJECT_ROOT}/spec/e2e/docker-compose.backfill.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-discovery-backfill
    ephemeral_ports KURA_US_PORT KURA_US_2_PORT TEMPO_PORT OTLP_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    if [ "${KURA_E2E_SKIP_BUILD:-0}" != "1" ]; then
      dc build kura-us kura-us-2 >/dev/null 2>&1
    fi
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
  AfterAll 'teardown_suite'

  It 'backfills pre-join state into a new node discovered through DNS'
    # Written before the new node exists, so no outbox message ever targets
    # it: presence on the joiner below proves the backfill walker moved the
    # data, not write-time replication.
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
    resolve_http_node KURA_US_2 kura-us-2

    wait_for_http "${KURA_US_2_URL}/up" || return 1
    capture_into us_ring wait_for_contains "${KURA_US_URL}/up" '"ring_members":2' || return 1
    capture_into us2_ring wait_for_contains "${KURA_US_2_URL}/up" '"ring_members":2' || return 1
    The variable us_ring should include '"ring_members":2'
    The variable us2_ring should include '"ring_members":2'

    capture_into us2_rollout \
      wait_for_contains "${KURA_US_2_URL}/status/rollout" \
      '"backfill_initial_cycle":"complete"' || return 1
    The variable us2_rollout should include '"backfill_initial_cycle":"complete"'

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
