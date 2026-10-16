# shellcheck shell=bash

# A node-local region (the BER1 rack's cache) replicating with a managed
# region it shares no network with: it dials the managed region's public peer
# host, and the managed region dials it through its in-cluster peer host. See
# test/e2e/docker-compose.node-local-peer.yml for the topology.

peer_status_from() {
  local service="$1" url="$2"
  docker exec "$(dc_container_id "$service")" sh -lc \
    "curl --fail --silent --show-error --max-time 5 --cacert /etc/kura/mtls/ca.pem --cert /etc/kura/mtls/peer.pem --key /etc/kura/mtls/peer.key ${url}/_internal/status"
}

unreachable_from() {
  local service="$1" url="$2"
  docker exec "$(dc_container_id "$service")" sh -lc \
    "curl --silent --max-time 5 --cacert /etc/kura/mtls/ca.pem --cert /etc/kura/mtls/peer.pem --key /etc/kura/mtls/peer.key ${url}/_internal/status >/dev/null 2>&1; printf '%s' \$?"
}

write_then_read() {
  local source="$1" key="$2"
  shift 2
  curl -fsS -X POST \
    "${source}/api/cache/cas/${key}?tenant_id=acme&namespace_id=ios" \
    -H 'content-type: application/octet-stream' --data-binary "$key" || return 1
  local target
  for target in "$@"; do
    wait_for_contains "${target}/api/cache/cas/${key}?tenant_id=acme&namespace_id=ios" "$key" 60 2 >/dev/null || return 1
  done
  printf 'replicated'
}

Describe 'node-local peer'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/test/e2e/docker-compose.node-local-peer.yml"
    )
    setup_suite_tmpdir
    local suffix="${SUITE_TMP_DIR##*.}"
    suite_env COMPOSE_PROJECT_NAME "kura-node-local-peer-${suffix,,}"
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT \
      GRAFANA_PORT PROMETHEUS_PORT LOKI_PORT TEMPO_PORT OTLP_PORT
    suite_env KURA_MTLS_CERT_DIR "${SUITE_TMP_DIR}/mtls"
    generate_peer_tls_material

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up public-demux rack-demux kura-us kura-ap kura-eu || return 1

    resolve_http_node KURA_US kura-us
    resolve_http_node KURA_AP kura-ap
    resolve_http_node KURA_EU kura-eu

    wait_for_node_ready "${KURA_US_URL}" || return 1
    wait_for_node_ready "${KURA_AP_URL}" || return 1
    wait_for_node_ready "${KURA_EU_URL}" || return 1
  }

  BeforeAll 'setup_suite'
  AfterAll 'compose_teardown'

  It 'reaches the rack only through its peer host, and the rack reaches out only through public peer hosts'
    capture_into direct_to_rack unreachable_from kura-us "https://10.254.254.17:7443"
    The variable direct_to_rack should not eq 0

    capture_into direct_to_cluster unreachable_from kura-eu "https://kura-ap.kura.internal:7443"
    The variable direct_to_cluster should not eq 0

    capture_into rack_status peer_status_from kura-us \
      "https://kura-acme-ber1-peer.tailscale-operator.svc.cluster.local:7443" || return 1
    The variable rack_status should include '"region":"ber1-runners"'
    The variable rack_status should include '"node_url":"https://kura-acme-ber1-peer.tailscale-operator.svc.cluster.local:7443"'

    capture_into managed_status peer_status_from kura-eu "https://peer.acme-eu-west-1.kura.test:7443" || return 1
    The variable managed_status should include '"region":"eu-west"'
    The variable managed_status should include '"node_url":"https://peer.acme-eu-west-1.kura.test:7443"'
  End

  It 'replicates a managed region write onto the rack'
    When call write_then_read "${KURA_US_URL}" node-local-from-managed "${KURA_EU_URL}"
    The status should be success
    The output should eq replicated
  End

  It 'replicates a rack write onto both replicas of the managed region'
    When call write_then_read "${KURA_EU_URL}" node-local-from-rack "${KURA_AP_URL}" "${KURA_US_URL}"
    The status should be success
    The output should eq replicated
  End
End
