# shellcheck shell=bash

Describe 'singleton handoff to joined nodes'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-handoff
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT \
      TEMPO_PORT OTLP_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc build kura-us kura-eu kura-ap >/dev/null 2>&1
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

  It 'moves singleton data to nodes that join later through the outbox'
    keyvalue_status="$(status_only -X PUT \
      "${KURA_US_URL}/api/cache/keyvalue?tenant_id=acme&namespace_id=handoff" \
      -H "content-type: application/json" \
      -d '{"cas_id":"handoff-1","entries":[{"value":"from-singleton"},{"value":"ready-for-join"}]}')"
    The variable keyvalue_status should eq 204

    capture_into singleton_body \
      wait_for_contains \
      "${KURA_US_URL}/api/cache/keyvalue/handoff-1?tenant_id=acme&namespace_id=handoff" \
      '"from-singleton"' || return 1
    The variable singleton_body should include '"from-singleton"'

    dc up -d kura-eu kura-ap >/dev/null 2>&1 || return 1
    resolve_http_node KURA_EU kura-eu
    resolve_http_node KURA_AP kura-ap

    wait_for_http "${KURA_EU_URL}/up" || return 1
    wait_for_http "${KURA_AP_URL}/up" || return 1
    capture_into us_ring wait_for_contains "${KURA_US_URL}/up" '"ring_members":3' || return 1
    capture_into eu_ring wait_for_contains "${KURA_EU_URL}/up" '"ring_members":3' || return 1
    capture_into ap_ring wait_for_contains "${KURA_AP_URL}/up" '"ring_members":3' || return 1
    The variable us_ring should include '"ring_members":3'
    The variable eu_ring should include '"ring_members":3'
    The variable ap_ring should include '"ring_members":3'

    capture_into eu_body \
      wait_for_contains \
      "${KURA_EU_URL}/api/cache/keyvalue/handoff-1?tenant_id=acme&namespace_id=handoff" \
      '"from-singleton"' || return 1
    The variable eu_body should include '"ready-for-join"'

    capture_into ap_body \
      wait_for_contains \
      "${KURA_AP_URL}/api/cache/keyvalue/handoff-1?tenant_id=acme&namespace_id=handoff" \
      '"from-singleton"' || return 1
    The variable ap_body should include '"ready-for-join"'
  End
End
