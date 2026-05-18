# shellcheck shell=bash

Describe 'peer mTLS'
  Include spec/e2e/support.sh

  setup_suite() {
    export COMPOSE_PROJECT_NAME="kura-mtls"
    export KURA_US_PORT=4501
    export KURA_EU_PORT=4502
    export KURA_AP_PORT=4503
    export GRAFANA_PORT=3400
    export PROMETHEUS_PORT=9290
    export LOKI_PORT=3210
    export TEMPO_PORT=3310
    export OTLP_PORT=4425
    export KURA_US_URL="http://localhost:${KURA_US_PORT}"
    export KURA_EU_URL="http://localhost:${KURA_EU_PORT}"
    export KURA_AP_URL="http://localhost:${KURA_AP_PORT}"

    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.mtls.yml"
    )
    setup_suite_tmpdir
    export KURA_MTLS_CERT_DIR="${SUITE_TMP_DIR}/mtls"
    generate_peer_tls_material

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc up --build -d >/dev/null 2>&1

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
End
