# shellcheck shell=bash

Describe 'tenant-scoped HTTP cache interoperability'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-tenant-scope
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT \
      KURA_US_GRPC_PORT KURA_EU_GRPC_PORT KURA_AP_GRPC_PORT

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

  It 'replicates and cleans tenant-scoped Xcode artifacts without a namespace'
    marker="account-binary-$(new_marker)"

    put_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/account-artifact?account_handle=acme" \
      -H "content-type: application/octet-stream" \
      --data-binary "${marker}")"
    The variable put_status should eq 204

    capture_into replicated_body \
      wait_for_contains "${KURA_EU_URL}/api/cache/cas/account-artifact?tenant_id=acme" "${marker}" || return 1
    The variable replicated_body should eq "${marker}"

    delete_status="$(status_only -X DELETE \
      "${KURA_AP_URL}/api/cache/clean?account_handle=acme")"
    The variable delete_status should eq 204

    capture_into missing_status \
      wait_for_status "${KURA_US_URL}/api/cache/cas/account-artifact?tenant_id=acme" 404 || return 1
    The variable missing_status should eq 404
  End
End
