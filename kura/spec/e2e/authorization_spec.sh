# shellcheck shell=bash

Describe 'cache authorization'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.auth.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-authorization
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us kura-eu kura-ap || return 1

    resolve_http_node KURA_US kura-us
    resolve_http_node KURA_EU kura-eu
    resolve_http_node KURA_AP kura-ap

    wait_for_http "${KURA_US_URL}/up"
    wait_for_http "${KURA_EU_URL}/up"
    wait_for_http "${KURA_AP_URL}/up"
    capture_into us_up wait_for_contains "${KURA_US_URL}/status/cluster" '"ring_members":3' || return 1
    capture_into eu_up wait_for_contains "${KURA_EU_URL}/status/cluster" '"ring_members":3' || return 1
    capture_into ap_up wait_for_contains "${KURA_AP_URL}/status/cluster" '"ring_members":3' || return 1
    [[ "${us_up}" == *'"ring_members":3'* ]]
    [[ "${eu_up}" == *'"ring_members":3'* ]]
    [[ "${ap_up}" == *'"ring_members":3'* ]]
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  It 'admits a token that grants the project and refuses one that does not'
    unauthorized_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/artifact-1?tenant_id=default&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "xcode-binary")"
    The variable unauthorized_status should eq 401

    capture_into ios_token jwt_for_namespace ios || return 1
    capture_into android_token jwt_for_namespace android || return 1
    The value "${ios_token}" should be present
    The value "${android_token}" should be present

    authorized_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/artifact-1?tenant_id=default&namespace_id=ios" \
      -H "authorization: Bearer ${ios_token}" \
      -H "content-type: application/octet-stream" \
      --data-binary "xcode-binary")"
    The variable authorized_status should eq 204

    # These nodes hold no route to a Tuist server, so a token whose grants do
    # not cover the request cannot be settled at all: the node reports that it
    # could not reach an answer rather than inventing one.
    unsettled_status="$(status_only \
      "${KURA_EU_URL}/api/cache/cas/artifact-1?tenant_id=default&namespace_id=ios" \
      -H "authorization: Bearer ${android_token}")"
    The variable unsettled_status should eq 503

    # A tenant this node does not serve is refused without leaving the node.
    wrong_tenant_status="$(status_only \
      "${KURA_US_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      -H "authorization: Bearer ${ios_token}")"
    The variable wrong_tenant_status should eq 403
  End

  It 'carries the principal through a replicated module cache upload'
    capture_into ios_token jwt_for_namespace ios || return 1

    capture_into start_response \
      curl -fsS -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=default&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" \
      -H "authorization: Bearer ${ios_token}" || return 1
    upload_id="$(extract_upload_id "${start_response}")"
    The value "${upload_id}" should be present

    part_one_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/part?upload_id=${upload_id}&part_number=1" \
      -H "authorization: Bearer ${ios_token}" \
      -H "content-type: application/octet-stream" \
      --data-binary "part-one-")"
    The variable part_one_status should eq 204

    part_two_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/part?upload_id=${upload_id}&part_number=2" \
      -H "authorization: Bearer ${ios_token}" \
      -H "content-type: application/octet-stream" \
      --data-binary "part-two")"
    The variable part_two_status should eq 204

    complete_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/complete?upload_id=${upload_id}" \
      -H "authorization: Bearer ${ios_token}" \
      -H "content-type: application/json" \
      -d '{"parts":[1,2]}')"
    The variable complete_status should eq 204

    wait_for_status_with \
      "${KURA_EU_URL}/api/cache/module/module-1?tenant_id=default&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" \
      200 \
      -H "authorization: Bearer ${ios_token}" >/dev/null || return 1

    body_file="${SUITE_TMP_DIR}/module.body"
    capture_into curl_output \
      curl -fsS \
      -o "${body_file}" \
      "${KURA_EU_URL}/api/cache/module/module-1?tenant_id=default&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" \
      -H "authorization: Bearer ${ios_token}" || return 1
    body="$(cat "${body_file}")"
    The variable body should eq 'part-one-part-two'
  End
End
