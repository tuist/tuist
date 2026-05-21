# shellcheck shell=bash

Describe 'default namespace routing'
  Include spec/e2e/support.sh

  setup_suite() {
    export COMPOSE_PROJECT_NAME="kura-default-namespace"
    export KURA_US_PORT=4601
    export KURA_EU_PORT=4602
    export KURA_AP_PORT=4603
    export KURA_US_URL="http://localhost:${KURA_US_PORT}"
    export KURA_EU_URL="http://localhost:${KURA_EU_PORT}"
    export KURA_AP_URL="http://localhost:${KURA_AP_PORT}"

    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.default-namespace.yml"
    )
    setup_suite_tmpdir

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us kura-eu kura-ap || return 1

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

  It 'accepts projectless Xcode cache requests when a default namespace is configured'
    status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/account-artifact?tenant_id=acme" \
      -H "content-type: application/octet-stream" \
      --data-binary "account-scoped-binary")"
    The variable status should eq 204

    capture_into body \
      wait_for_contains \
      "${KURA_EU_URL}/api/cache/cas/account-artifact?tenant_id=acme" \
      'account-scoped-binary' || return 1
    The variable body should eq 'account-scoped-binary'
  End
End
