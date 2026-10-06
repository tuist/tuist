# shellcheck shell=bash

Describe 'peer mTLS'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.mtls.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-mtls
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT \
      GRAFANA_PORT PROMETHEUS_PORT LOKI_PORT TEMPO_PORT OTLP_PORT
    suite_env KURA_MTLS_CERT_DIR "${SUITE_TMP_DIR}/mtls"
    generate_peer_tls_material

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us kura-eu kura-ap || return 1

    resolve_http_node KURA_US kura-us
    resolve_http_node KURA_EU kura-eu
    resolve_http_node KURA_AP kura-ap

    wait_for_node_ready "${KURA_US_URL}"
    wait_for_node_ready "${KURA_EU_URL}"
    wait_for_node_ready "${KURA_AP_URL}"
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

  It 'requires client certificates on internal endpoints while replication still works'
    public_status="$(status_only "${KURA_US_URL}/_internal/status")"
    The variable public_status should eq 404

    kura_us_container="$(dc_container_id kura-us)"
    The value "${kura_us_container}" should be present

    capture_into missing_cert_status \
      docker exec "${kura_us_container}" sh -lc \
      "curl --fail --silent --show-error --cacert /etc/kura/mtls/ca.pem https://kura-eu.kura.internal:7443/_internal/status >/dev/null 2>&1; printf '%s' \$?" || return 1
    The variable missing_cert_status should not eq 0

    capture_into peer_status_output \
      docker exec "${kura_us_container}" sh -lc \
      "curl --fail --silent --show-error --cacert /etc/kura/mtls/ca.pem --cert /etc/kura/mtls/peer.pem --key /etc/kura/mtls/peer.key https://kura-eu.kura.internal:7443/_internal/status" || return 1
    The variable peer_status_output should include '"node_url":"https://kura-eu.kura.internal:7443"'
    The variable peer_status_output should include '"provider":"ovh"'
    The variable peer_status_output should include '"private_url":"https://private-eu.kura.internal:7443"'

    artifact_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/cas/mtls-artifact?tenant_id=acme&namespace_id=ios" \
      -H "content-type: application/octet-stream" \
      --data-binary "mtls-binary")"
    The variable artifact_status should eq 204

    capture_into replicated_artifact \
      wait_for_contains \
      "${KURA_EU_URL}/api/cache/cas/mtls-artifact?tenant_id=acme&namespace_id=ios" \
      'mtls-binary' || return 1
    The variable replicated_artifact should eq 'mtls-binary'
  End

  all_origins_replicate() {
    local origin=0 source target body
    for source in "${KURA_US_URL}" "${KURA_EU_URL}" "${KURA_AP_URL}"; do
      body="topology-origin-${origin}"
      curl -fsS -X POST \
        "${source}/api/cache/cas/${body}?tenant_id=acme&namespace_id=ios" \
        -H 'content-type: application/octet-stream' --data-binary "$body" || return 1
      for target in "${KURA_US_URL}" "${KURA_EU_URL}" "${KURA_AP_URL}"; do
        wait_for_contains "${target}/api/cache/cas/${body}?tenant_id=acme&namespace_id=ios" "$body" >/dev/null || return 1
      done
      origin=$((origin + 1))
    done
    printf 'replicated'
  }

  It 'retains all origins and both directions across providers with private peers preferred'
    When call all_origins_replicate
    The status should be success
    The output should eq replicated
  End

  regional_origins_replicate() {
    COMPOSE_FILES+=(-f "${PROJECT_ROOT}/test/e2e/docker-compose.mtls-regional.yml")
    dc down -v --remove-orphans >/dev/null 2>&1 || return 1
    compose_up kura-us kura-eu kura-ap || return 1
    resolve_http_node KURA_US kura-us
    resolve_http_node KURA_EU kura-eu
    resolve_http_node KURA_AP kura-ap
    wait_for_node_ready "${KURA_US_URL}" >/dev/null || return 1
    wait_for_node_ready "${KURA_EU_URL}" >/dev/null || return 1
    wait_for_node_ready "${KURA_AP_URL}" >/dev/null || return 1
    all_origins_replicate
  }

  It 'replicates within a private VPC and between reciprocally approved VPCs'
    When call regional_origins_replicate
    The status should be success
    The output should eq replicated
  End
End
