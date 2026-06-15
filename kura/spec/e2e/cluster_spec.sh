# shellcheck shell=bash

Describe 'core cluster behaviour'
  Include spec/e2e/support.sh

  resolve_endpoints() {
    resolve_http_node KURA_US kura-us
    resolve_http_node KURA_EU kura-eu
    resolve_http_node KURA_AP kura-ap
    resolve_http_node GRAFANA grafana 3000
    resolve_http_node PROMETHEUS prometheus 9090
  }

  setup_suite() {
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-e2e
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT \
      KURA_US_GRPC_PORT KURA_EU_GRPC_PORT KURA_AP_GRPC_PORT \
      GRAFANA_PORT PROMETHEUS_PORT LOKI_PORT TEMPO_PORT OTLP_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up || return 1

    resolve_endpoints

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
  Before 'resolve_endpoints'
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
    resolve_http_node KURA_EU kura-eu
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

    capture_into head_status \
      wait_for_head_status \
      "${KURA_EU_URL}/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" \
      204 || return 1
    The variable head_status should eq 204

    capture_into module_body \
      wait_for_contains \
      "${KURA_EU_URL}/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds" \
      'part-one-part-two' || return 1
    The variable module_body should eq 'part-one-part-two'
  End

  It 'keeps module artifacts larger than one segment readable after a node restart'
    marker="$(new_marker)"
    module_id="large-module-${marker}"
    module_hash="large-hash-${marker}"
    module_name="LargeModule-${marker}.framework"
    # Kura assembles module-cache parts into one artifact before persistence.
    # 52 * 10 MiB = 520 MiB, just over Kura's 512 MiB segment size.
    module_part_size=$((10 * 1024 * 1024))
    module_part_count=52
    module_size=$((module_part_size * module_part_count))
    expected_path="${SUITE_TMP_DIR}/large-module-${marker}.bin"
    part_path="${SUITE_TMP_DIR}/large-module-part-${marker}.bin"
    before_restart_path="${SUITE_TMP_DIR}/large-module-before-${marker}.bin"
    after_restart_path="${SUITE_TMP_DIR}/large-module-after-${marker}.bin"

    : >"${expected_path}"
    capture_into start_response \
      curl -fsS -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=${module_hash}&name=${module_name}&cache_category=builds" || return 1
    upload_id="$(extract_upload_id "${start_response}")"
    The value "${upload_id}" should be present

    parts_json=""
    for part_number in $(seq 1 "${module_part_count}"); do
      head -c "${module_part_size}" /dev/zero >"${part_path}" || return 1
      cat "${part_path}" >>"${expected_path}"

      part_status="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/module/part?upload_id=${upload_id}&part_number=${part_number}" \
        -H "content-type: application/octet-stream" \
        --data-binary "@${part_path}")"
      if [ "${part_status}" != "204" ]; then
        printf 'module part %s returned %s\n' "${part_number}" "${part_status}" >&2
        return 1
      fi

      rm -f "${part_path}"
      if [ -n "${parts_json}" ]; then
        parts_json="${parts_json},"
      fi
      parts_json="${parts_json}${part_number}"
    done
    expected_size="$(wc -c <"${expected_path}" | tr -d '[:space:]')"
    The variable expected_size should eq "${module_size}"

    complete_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/complete?upload_id=${upload_id}" \
      -H "content-type: application/json" \
      -d "{\"parts\":[${parts_json}]}")"
    The variable complete_status should eq 204

    module_url="${KURA_US_URL}/api/cache/module/${module_id}?tenant_id=acme&namespace_id=ios&hash=${module_hash}&name=${module_name}&cache_category=builds"
    capture_into head_status wait_for_head_status "${module_url}" 204 || return 1
    The variable head_status should eq 204

    curl -fsS "${module_url}" -o "${before_restart_path}" || return 1
    before_restart_size="$(wc -c <"${before_restart_path}" | tr -d '[:space:]')"
    The variable before_restart_size should eq "${module_size}"
    before_restart_match="$(cmp -s "${expected_path}" "${before_restart_path}" && echo match || echo differ)"
    The variable before_restart_match should eq "match"

    dc restart kura-us >/dev/null 2>&1 || return 1
    resolve_http_node KURA_US kura-us
    wait_for_http "${KURA_US_URL}/up" || return 1
    capture_into us_up wait_for_contains "${KURA_US_URL}/up" '"ring_members":3' || return 1
    The variable us_up should include '"ring_members":3'

    module_url="${KURA_US_URL}/api/cache/module/${module_id}?tenant_id=acme&namespace_id=ios&hash=${module_hash}&name=${module_name}&cache_category=builds"
    capture_into restarted_head_status wait_for_head_status "${module_url}" 204 || return 1
    The variable restarted_head_status should eq 204

    curl -fsS "${module_url}" -o "${after_restart_path}" || return 1
    after_restart_size="$(wc -c <"${after_restart_path}" | tr -d '[:space:]')"
    The variable after_restart_size should eq "${module_size}"
    after_restart_match="$(cmp -s "${expected_path}" "${after_restart_path}" && echo match || echo differ)"
    The variable after_restart_match should eq "match"
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
