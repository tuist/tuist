# shellcheck shell=bash

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

  It 'retains all origins and both directions across providers with private peers preferred'
    When call all_origins_replicate
    The status should be success
    The output should eq replicated
  End

End

setup_regional_suite() {
  COMPOSE_FILES=(
    -f "${PROJECT_ROOT}/docker-compose.yml"
    -f "${PROJECT_ROOT}/test/e2e/docker-compose.mtls.yml"
    -f "${PROJECT_ROOT}/test/e2e/docker-compose.mtls-regional.yml"
  )
  if [ "$1" = unapproved ]; then
    COMPOSE_FILES+=(-f "${PROJECT_ROOT}/test/e2e/docker-compose.mtls-regional-unapproved.yml")
  fi
  setup_suite_tmpdir
  local suffix="${SUITE_TMP_DIR##*.}"
  suite_env COMPOSE_PROJECT_NAME "kura-mtls-regional-$1-${suffix,,}"
  ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT \
    GRAFANA_PORT PROMETHEUS_PORT LOKI_PORT TEMPO_PORT OTLP_PORT
  suite_env KURA_MTLS_CERT_DIR "${SUITE_TMP_DIR}/mtls"
  generate_peer_tls_material
  local members=3
  local services=(private-us private-eu kura-us kura-eu kura-ap)
  if [ "$1" = unapproved ]; then
    services+=(kura-ap-sibling)
    members=4
  fi
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  compose_up "${services[@]}" || return 1
  resolve_http_node KURA_US kura-us
  resolve_http_node KURA_EU kura-eu
  resolve_http_node KURA_AP kura-ap
  for endpoint in "${KURA_US_URL}" "${KURA_EU_URL}" "${KURA_AP_URL}"; do
    wait_for_node_ready "$endpoint" >/dev/null || return 1
    wait_for_contains "$endpoint/status/cluster" "\"ring_members\":$members" >/dev/null || return 1
    if [ "$1" = unapproved ]; then
      wait_for_contains "$endpoint/status/cluster" 'https://kura-ap-sibling.kura.internal:7443' >/dev/null || return 1
    fi
  done
}

Describe 'approved regional peer mTLS'
  Include spec/e2e/support.sh
  BeforeAll 'setup_regional_suite approved'
  AfterAll 'compose_teardown'

  regional_paths_replicate() {
    # No ORD peer may reach the SCL private alias (and vice versa).
    local container
    container="$(dc_container_id kura-us)"
    docker exec "$container" getent hosts kura-ap.kura.internal >/dev/null || return 1
    if docker exec "$container" getent hosts private-ap.kura.internal >/dev/null 2>&1; then return 1; fi
    container="$(dc_container_id kura-ap)"
    docker exec "$container" getent hosts kura-us.kura.internal >/dev/null || return 1
    if docker exec "$container" getent hosts private-us.kura.internal >/dev/null 2>&1; then return 1; fi
    all_origins_replicate >/dev/null || return 1
    # Status probes alone cannot satisfy this assertion. Both ORD directions
    # must have transferred bodies through their private-only mTLS proxies.
    local proxy logs
    for proxy in private-us private-eu; do
      logs="$(dc logs --no-color "$proxy")" || return 1
      [[ "$logs" == *'200 POST /_internal/backfill/bodies'* ]] || return 1
    done
    printf replicated
  }

  It 'uses private body paths within a VPC and canonical paths across approved VPCs'
    When call regional_paths_replicate
    The status should be success
    The output should eq replicated
  End
End

Describe 'unapproved regional peer mTLS'
  Include spec/e2e/support.sh
  BeforeAll 'setup_regional_suite unapproved'
  AfterAll 'compose_teardown'

  unapproved_domain_is_isolated() {
    curl -fsS -X POST "${KURA_AP_URL}/api/cache/cas/unapproved-origin?tenant_id=acme&namespace_id=ios" \
      -H 'content-type: application/octet-stream' --data-binary 'unapproved-payload' || return 1
    # Both domains are live; SCL has a healthy same-domain sibling.
    local sibling attempt endpoint status
    sibling="$(dc_container_id kura-ap-sibling)"
    local private_copy=""
    for attempt in $(seq 1 30); do
      private_copy="$(docker exec "$sibling" curl -fsS 'http://localhost:4000/api/cache/cas/unapproved-origin?tenant_id=acme&namespace_id=ios' 2>/dev/null || true)"
      [ "$private_copy" = unapproved-payload ] && break
      sleep 1
    done
    [ "$private_copy" = unapproved-payload ] || return 1
    # The fixture is healthy and knows all four peers before this write.
    # Observe repeated replication opportunities, not a single immediate miss.
    for attempt in $(seq 1 30); do
      for endpoint in "${KURA_US_URL}" "${KURA_EU_URL}"; do
        status="$(status_only "$endpoint/api/cache/cas/unapproved-origin?tenant_id=acme&namespace_id=ios")"
        [ "$status" = 404 ] || return 1
      done
      sleep 1
    done
    wait_for_contains "${KURA_AP_URL}/api/cache/cas/unapproved-origin?tenant_id=acme&namespace_id=ios" 'unapproved-payload' >/dev/null || return 1
    printf isolated
  }

  It 'keeps a one-sided approval from replicating into the other domain'
    When call unapproved_domain_is_isolated
    The status should be success
    The output should eq isolated
  End
End
