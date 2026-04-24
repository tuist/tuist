# shellcheck shell=bash

Describe 'core cluster behaviour'
  Include spec/e2e/support.sh

  setup_suite() {
    export COMPOSE_PROJECT_NAME="kura-e2e"
    export KURA_US_PORT=4201
    export KURA_EU_PORT=4202
    export KURA_AP_PORT=4203
    export GRAFANA_PORT=3300
    export PROMETHEUS_PORT=9190
    export LOKI_PORT=3201
    export TEMPO_PORT=3301
    export OTLP_PORT=4418
    export KURA_US_URL="http://localhost:${KURA_US_PORT}"
    export KURA_EU_URL="http://localhost:${KURA_EU_PORT}"
    export KURA_AP_URL="http://localhost:${KURA_AP_PORT}"
    export GRAFANA_URL="http://localhost:${GRAFANA_PORT}"
    export PROMETHEUS_URL="http://localhost:${PROMETHEUS_PORT}"

    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc up --build -d >/dev/null 2>&1

    wait_for_http "${KURA_US_URL}/up"
    wait_for_http "${KURA_EU_URL}/up"
    wait_for_http "${KURA_AP_URL}/up"
    capture_into us_up wait_for_contains "${KURA_US_URL}/up" '"ring_members":3' || return 1
    capture_into eu_up wait_for_contains "${KURA_EU_URL}/up" '"ring_members":3' || return 1
    capture_into ap_up wait_for_contains "${KURA_AP_URL}/up" '"ring_members":3' || return 1
    wait_for_http "${GRAFANA_URL}/api/health"
    wait_for_http "${PROMETHEUS_URL}/-/ready"
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  It 'syncs keyvalue entries across regions'
    status="$(status_only -X PUT \
      "${KURA_US_URL}/api/cache/keyvalue?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/json" \
      -d '{"cas_id":"cas-1","entries":[{"value":"hello"},{"value":"world"}]}')"
    The variable status should eq 204

    capture_into body \
      wait_for_contains \
      "${KURA_EU_URL}/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios" \
      '"hello"' || return 1
    The variable body should include '"hello"'
    The variable body should include '"world"'
  End

  It 'keeps Xcode artifacts readable after a node restart'
    status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "xcode-binary")"
    The variable status should eq 204

    capture_into body \
      wait_for_contains \
      "${KURA_EU_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      'xcode-binary' || return 1
    The variable body should eq 'xcode-binary'

    dc restart kura-eu >/dev/null 2>&1 || return 1
    wait_for_http "${KURA_EU_URL}/up" || return 1
    capture_into eu_up wait_for_contains "${KURA_EU_URL}/up" '"ring_members":3' || return 1
    The variable eu_up should include '"ring_members":3'

    capture_into restarted_body \
      wait_for_contains \
      "${KURA_EU_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
      'xcode-binary' || return 1
    The variable restarted_body should eq 'xcode-binary'
  End

  It 'syncs Gradle artifacts to another region'
    status="$(status_only -X PUT \
      "${KURA_EU_URL}/api/cache/gradle/gradle-key-1?tenant_id=acme&namespace_id=android" \
      -H "content-type: application/octet-stream" \
      --data-binary "gradle-cache")"
    The variable status should eq 201

    capture_into body \
      wait_for_contains \
      "${KURA_AP_URL}/api/cache/gradle/gradle-key-1?tenant_id=acme&namespace_id=android" \
      'gradle-cache' || return 1
    The variable body should include 'gradle-cache'
  End

  It 'makes multipart module uploads visible from another node'
    capture_into start_response \
      curl -fsS -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" || return 1
    upload_id="$(extract_upload_id "${start_response}")"
    The value "${upload_id}" should be present

    part_one_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/part?upload_id=${upload_id}&part_number=1" \
      -H "content-type: application/octet-stream" \
      --data-binary "part-one-")"
    The variable part_one_status should eq 204

    part_two_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/part?upload_id=${upload_id}&part_number=2" \
      -H "content-type: application/octet-stream" \
      --data-binary "part-two")"
    The variable part_two_status should eq 204

    complete_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/complete?upload_id=${upload_id}" \
      -H "content-type: application/json" \
      -d '{"parts":[1,2]}')"
    The variable complete_status should eq 204

    head_status="$(status_only -I \
      "${KURA_EU_URL}/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")"
    The variable head_status should eq 204

    capture_into module_body \
      wait_for_contains \
      "${KURA_EU_URL}/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" \
      'part-one-part-two' || return 1
    The variable module_body should eq 'part-one-part-two'
  End

  It 'removes namespace artifacts across the cluster on clean'
    delete_status="$(status_only -X DELETE \
      "${KURA_AP_URL}/api/cache/clean?tenant_id=acme&namespace_id=ios")"
    The variable delete_status should eq 204

    cas_status="$(status_only \
      "${KURA_US_URL}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios")"
    The variable cas_status should eq 404

    keyvalue_status="$(status_only \
      "${KURA_EU_URL}/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios")"
    The variable keyvalue_status should eq 404
  End

  It 'keeps the observability stack reachable'
    capture_into grafana_health curl -fsS "${GRAFANA_URL}/api/health" || return 1
    The variable grafana_health should include '"database": "ok"'

    capture_into prometheus_query \
      wait_for_all_contains \
      "${PROMETHEUS_URL}/api/v1/query?query=kura_node_info" \
      'us-east' \
      'eu-west' \
      'ap-south' || return 1
    The variable prometheus_query should include 'us-east'
    The variable prometheus_query should include 'eu-west'
    The variable prometheus_query should include 'ap-south'

    capture_into metrics_output curl -fsS "${KURA_US_URL}/metrics" || return 1
    The variable metrics_output should include 'kura_http_requests_total'
  End
End
