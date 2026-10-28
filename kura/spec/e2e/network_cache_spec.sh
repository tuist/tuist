# shellcheck shell=bash

Describe 'network-trusted self-hosted cache access'
  Include spec/e2e/support.sh
  Skip if 'native Kura binary is not configured' test -z "${KURA_NETWORK_CACHE_TEST_BIN:-}"

  setup_network_cache() {
    NETWORK_TMP="$(mktemp -d)"
    export KURA_MTLS_CERT_DIR="$NETWORK_TMP"
    generate_peer_tls_material || return 1
    node test/e2e/network-cache/control_plane.mjs "$NETWORK_TMP" >"$NETWORK_TMP/control.log" 2>&1 &
    CONTROL_PID=$!
    for _ in $(seq 1 100); do
      [ -s "$NETWORK_TMP/ports" ] && break
      sleep 0.1
    done
    [ -s "$NETWORK_TMP/ports" ] || return 1
    read -r CONTROL_PORT PORT INTERNAL_PORT < "$NETWORK_TMP/ports"
    CONTROL_URL="http://127.0.0.1:$CONTROL_PORT"
    NETWORK_URL="http://127.0.0.1:$PORT"
    env -i PATH="$PATH" KURA_PORT="$PORT" KURA_INTERNAL_PORT="$INTERNAL_PORT" \
      KURA_TENANT_ID=acme KURA_REGION=local KURA_NODE_URL="https://127.0.0.1:$INTERNAL_PORT" \
      KURA_INTERNAL_TLS_CA_CERT_PATH="$NETWORK_TMP/ca.pem" \
      KURA_INTERNAL_TLS_CERT_PATH="$NETWORK_TMP/peer.pem" KURA_INTERNAL_TLS_KEY_PATH="$NETWORK_TMP/peer.key" \
      KURA_DATA_DIR="$NETWORK_TMP/data" KURA_TMP_DIR="$NETWORK_TMP/tmp" \
      KURA_MEMORY_SOFT_LIMIT_BYTES=536870912 KURA_MEMORY_HARD_LIMIT_BYTES=805306368 \
      KURA_METADATA_STORE_READ_CACHE_BYTES=16777216 KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES=16777216 \
      KURA_METADATA_STORE_WRITE_BUFFER_BYTES=4194304 KURA_METADATA_STORE_MAX_OPEN_FILES=256 \
      KURA_FILE_DESCRIPTOR_POOL_SIZE=256 KURA_OTEL_SERVICE_NAME=network-cache-test KURA_OTEL_DEPLOYMENT_ENVIRONMENT=local \
      KURA_AUTH_TUIST_URL="$CONTROL_URL" KURA_CONTROL_PLANE_URL="$CONTROL_URL" \
      KURA_CONTROL_PLANE_CLIENT_ID=test KURA_CONTROL_PLANE_CLIENT_SECRET=test KURA_MESH_PEERS_SYNC=true \
      RUST_LOG=warn "$KURA_NETWORK_CACHE_TEST_BIN" >"$NETWORK_TMP/kura.log" 2>&1 &
    KURA_PID=$!
    for _ in $(seq 1 200); do
      curl -fsS "$NETWORK_URL/ready" >/dev/null 2>&1 && return 0
      sleep 0.1
    done
    cat "$NETWORK_TMP/kura.log" >&2
    return 1
  }

  teardown_network_cache() {
    [ -z "${KURA_PID:-}" ] || kill "$KURA_PID" 2>/dev/null || true
    [ -z "${CONTROL_PID:-}" ] || kill "$CONTROL_PID" 2>/dev/null || true
    wait "${KURA_PID:-}" "${CONTROL_PID:-}" 2>/dev/null || true
    rm -rf "${NETWORK_TMP:?}"
  }

  cache_roundtrip() {
    local entry="$NETWORK_URL/api/cache/gradle/key?tenant_id=acme&namespace_id=ios"
    curl -fsS -X PUT --data-binary 'network cache bytes' "$entry" >/dev/null || return 1
    [ "$(curl -fsS "$entry")" = 'network cache bytes' ] || return 1
    for credential in 'Authorization;' 'Authorization: Bearer' 'Authorization: Bearer rejected'; do
      local status
      status="$(curl -sS -o /dev/null -w '%{http_code}' -H "$credential" "$entry")"
      [ "$status" != 200 ] || return 1
    done
    [ "$(curl -sS -o /dev/null -w '%{http_code}' -H 'Authorization: one' -H 'Authorization: two' "$entry")" = 401 ] || return 1
    [ "$(curl -sS -o /dev/null -w '%{http_code}' "$NETWORK_URL/api/cache/gradle/key?tenant_id=other&namespace_id=ios")" != 200 ] || return 1
    [ "$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$NETWORK_URL/api/cache?tenant_id=acme&namespace_id=ios")" != 200 ] || return 1
    printf '\000\000\000\000\000' >"$NETWORK_TMP/empty.grpc"
    curl -fsS --http2-prior-knowledge -D "$NETWORK_TMP/grpc.headers" -o /dev/null \
      -H 'content-type: application/grpc' -H 'te: trailers' --data-binary @"$NETWORK_TMP/empty.grpc" \
      "$NETWORK_URL/build.bazel.remote.execution.v2.Capabilities/GetCapabilities" || return 1
    grep -qi '^grpc-status: 0' "$NETWORK_TMP/grpc.headers" || return 1
    # The HTTP and gRPC requests share one policy fill despite distinct projects.
    [ "$(curl -fsS "$CONTROL_URL/calls" | node -e 'let text=""; for await (const chunk of process.stdin) text+=chunk; console.log(JSON.parse(text).policyCalls)')" = 1 ]
  }

  policy_expiry() {
    local mode="$1" entry="$NETWORK_URL/api/cache/gradle/key?tenant_id=acme&namespace_id=ios"
    curl -fsS -X PUT --data-binary 'retained bytes' "$entry" >/dev/null || return 1
    curl -fsS -X POST "$CONTROL_URL/policy/$mode" >/dev/null || return 1
    # Exercise natural expiry, not a test-only cache invalidation hook.
    sleep 61
    [ "$(curl -sS -o /dev/null -w '%{http_code}' "$entry")" = 401 ] || return 1
    [ "$(curl -fsS -H 'Authorization: Bearer valid' "$entry")" = 'retained bytes' ]
  }

  healthy_policy_expiry() {
    local entry="$NETWORK_URL/api/cache/gradle/key?tenant_id=acme&namespace_id=ios"
    curl -fsS -X POST "$CONTROL_URL/policy/delayed" >/dev/null || return 1
    curl -fsS -X PUT --data-binary 'retained bytes' "$entry" >/dev/null || return 1
    # Consult after lookup-start expiry but before insertion-based expiry.
    # Assert the actual refresh timestamp so a late runner cannot mask the bug.
    node --input-type=module - "$CONTROL_URL" "$entry" <<'JS'
const [control, entry] = process.argv.slice(2);
const first = await (await fetch(`${control}/calls`)).json();
await new Promise((resolve) => setTimeout(resolve, Math.max(0, first.policyStartedAt + 60100 - Date.now())));
const response = await fetch(entry);
if (!response.ok || await response.text() !== "retained bytes") throw new Error("healthy policy refresh failed");
const next = await (await fetch(`${control}/calls`)).json();
if (next.policyCalls !== first.policyCalls + 1 || next.policyStartedAt >= first.policyCompletedAt + 60000) {
  throw new Error("policy refresh missed the distinguishing expiry window");
}
JS
  }

  BeforeEach 'setup_network_cache'
  AfterEach 'teardown_network_cache'

  It 'transfers bytes over HTTP and probes gRPC without broadening supplied credentials'
    When call cache_roundtrip
    The status should be success
    The output should be blank
  End

  It 'refreshes expired policy without refusing healthy unsigned traffic'
    When call healthy_policy_expiry
    The status should be success
    The output should be blank
  End

  Parameters:value disabled outage
  It "denies unsigned traffic after policy expiry on $1 while preserving authenticated traffic"
    When call policy_expiry "$1"
    The status should be success
    The output should be blank
  End
End
