# shellcheck shell=bash

Describe 'extension hooks'
  Include spec/e2e/support.sh

  setup_suite() {
    export COMPOSE_PROJECT_NAME="kura-extension"
    export KURA_US_PORT=4501
    export KURA_EU_PORT=4502
    export KURA_AP_PORT=4503
    export KURA_US_URL="http://localhost:${KURA_US_PORT}"
    export KURA_EU_URL="http://localhost:${KURA_EU_PORT}"
    export KURA_AP_URL="http://localhost:${KURA_AP_PORT}"

    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.extension.yml"
    )
    setup_suite_tmpdir

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc up --build -d kura-us kura-eu kura-ap >/dev/null 2>&1

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

  It 'enforces authz and signs module cache responses'
    unauthorized_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "xcode-binary")"
    The variable unauthorized_status should eq 401

    capture_into ios_token jwt_for_namespace ios || return 1
    capture_into android_token jwt_for_namespace android || return 1
    The value "${ios_token}" should be present
    The value "${android_token}" should be present

    authorized_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      -H "authorization: Bearer ${ios_token}" \
      -H "content-type: application/octet-stream" \
      --data-binary "xcode-binary")"
    The variable authorized_status should eq 204

    forbidden_status="$(status_only \
      "${KURA_EU_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      -H "authorization: Bearer ${android_token}")"
    The variable forbidden_status should eq 403

    capture_into start_response \
      curl -fsS -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" \
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

    headers_file="${SUITE_TMP_DIR}/module.headers"
    body_file="${SUITE_TMP_DIR}/module.body"
    capture_into curl_output \
      curl -fsS \
      -D "${headers_file}" \
      -o "${body_file}" \
      "${KURA_EU_URL}/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" \
      -H "authorization: Bearer ${ios_token}" || return 1
    body="$(cat "${body_file}")"
    signature="$(awk 'BEGIN {IGNORECASE=1} /^x-cache-signature:/ {print $2}' "${headers_file}" | tr -d '\r')"
    expected="$(expected_signature hash-1)"
    The variable body should eq 'part-one-part-two'
    The value "${signature}" should be present
    The variable signature should eq "${expected}"
  End
End
