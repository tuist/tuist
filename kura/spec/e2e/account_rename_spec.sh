# shellcheck shell=bash

Describe 'account rename through managed discovery'
  Include spec/e2e/support.sh
  Skip if 'native Kura binary is not configured' test -z "${KURA_RENAME_TEST_BIN:-}"

  setup_rename() {
    RENAME_TMP="$(mktemp -d)"
    KURA_MTLS_CERT_DIR="$RENAME_TMP"
    generate_peer_tls_material || return 1
    node test/e2e/account-rename/control_plane.mjs "$RENAME_TMP" >"$RENAME_TMP/control.log" 2>&1 &
    CONTROL_PID=$!
    for _ in $(seq 1 100); do
      [ -s "$RENAME_TMP/control-port" ] && break
      kill -0 "$CONTROL_PID" 2>/dev/null || { cat "$RENAME_TMP/control.log" >&2; return 1; }
      sleep 0.1
    done
    [ -s "$RENAME_TMP/control-port" ] || { cat "$RENAME_TMP/control.log" >&2; return 1; }
    CONTROL_URL="http://127.0.0.1:$(cat "$RENAME_TMP/control-port")"
    read -r PORT INTERNAL_PORT < "$RENAME_TMP/kura-ports"
    RENAME_URL="http://127.0.0.1:$PORT"
    env -i PATH="$PATH" KURA_PORT="$PORT" KURA_INTERNAL_PORT="$INTERNAL_PORT" \
      KURA_TENANT_ID=original KURA_REGION=local KURA_NODE_URL="https://127.0.0.1:$INTERNAL_PORT" \
      KURA_INTERNAL_TLS_CA_CERT_PATH="$RENAME_TMP/ca.pem" KURA_INTERNAL_TLS_CERT_PATH="$RENAME_TMP/peer.pem" KURA_INTERNAL_TLS_KEY_PATH="$RENAME_TMP/peer.key" \
      KURA_DATA_DIR="$RENAME_TMP/data" KURA_TMP_DIR="$RENAME_TMP/tmp" \
      KURA_MEMORY_SOFT_LIMIT_BYTES=536870912 KURA_MEMORY_HARD_LIMIT_BYTES=805306368 \
      KURA_METADATA_STORE_READ_CACHE_BYTES=16777216 KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES=16777216 \
      KURA_METADATA_STORE_WRITE_BUFFER_BYTES=4194304 KURA_METADATA_STORE_MAX_OPEN_FILES=256 \
      KURA_FILE_DESCRIPTOR_POOL_SIZE=256 KURA_OTEL_SERVICE_NAME=rename-test KURA_OTEL_DEPLOYMENT_ENVIRONMENT=local \
      KURA_AUTH_TUIST_URL="$CONTROL_URL" KURA_CONTROL_PLANE_URL="$CONTROL_URL" \
      KURA_CONTROL_PLANE_CLIENT_ID=test KURA_CONTROL_PLANE_CLIENT_SECRET=test KURA_MESH_PEERS_SYNC=true \
      RUST_LOG=warn "$KURA_RENAME_TEST_BIN" >"$RENAME_TMP/kura.log" 2>&1 &
    KURA_PID=$!
    for _ in $(seq 1 100); do
      curl -fsS "$RENAME_URL/ready" >/dev/null 2>&1 && return 0
      sleep 0.1
    done
    cat "$RENAME_TMP/kura.log" >&2
    return 1
  }

  teardown_rename() {
    kill "$KURA_PID" "$CONTROL_PID" 2>/dev/null || true
    wait "$KURA_PID" "$CONTROL_PID" 2>/dev/null || true
    rm -rf "${RENAME_TMP:?}"
  }

  rename_roundtrip() {
    curl -fsS -X PUT -H 'Authorization: Bearer test' --data-binary 'cached before rename' \
      "$RENAME_URL/api/cache/gradle/key?tenant_id=original&namespace_id=ios" >/dev/null || return 1
    curl -fsS -X POST "$CONTROL_URL/rename" >/dev/null || return 1
    for _ in $(seq 1 100); do
      status=$(curl -sS -o "$RENAME_TMP/body" -w '%{http_code}' -H 'Authorization: Bearer test' \
        "$RENAME_URL/api/cache/gradle/key?tenant_id=renamed&namespace_id=ios")
      [ "$status" = 200 ] && break
      sleep 0.1
    done
    [ "$status" = 200 ] && [ "$(cat "$RENAME_TMP/body")" = 'cached before rename' ] || { printf 'rename read status: %s\n' "$status" >&2; cat "$RENAME_TMP/body" "$RENAME_TMP/kura.log" >&2; return 1; }
    for step in 'rename-again latest' 'rename-back original'; do
      read -r action canonical <<< "$step"
      curl -fsS -X POST "$CONTROL_URL/$action" >/dev/null || return 1
      # A Host override exercises the real runtime's redirect path locally;
      # the controller suite separately validates real DNS/TLS/ingress renders.
      source=renamed.example.com
      for _ in $(seq 1 100); do
        status=$(curl -sS -o /dev/null -D "$RENAME_TMP/headers" -w '%{http_code}' \
          -H 'Authorization: Bearer test' -H "Host: $source" -H 'x-tuist-accept-endpoint-redirect: 1' \
          "$RENAME_URL/api/cache/gradle/key?tenant_id=renamed&namespace_id=ios")
        if [ "$status" = 307 ] && grep -qi "location: https://$canonical.example.com/api/cache/gradle/key?tenant_id=renamed&namespace_id=ios" "$RENAME_TMP/headers"; then break; fi
        sleep 0.1
      done
      [ "$status" = 307 ] || return 1
      grep -qi "location: https://$canonical.example.com/api/cache/gradle/key?tenant_id=renamed&namespace_id=ios" "$RENAME_TMP/headers" || return 1
      grep -qi 'cache-control: no-store' "$RENAME_TMP/headers" || return 1
      for alias in original renamed latest; do
        [ "$(curl -fsS -H 'Authorization: Bearer test' -H "Host: $alias.example.com" "$RENAME_URL/api/cache/gradle/key?tenant_id=$alias&namespace_id=ios")" = 'cached before rename' ] || return 1
      done
    done
    [ "$(curl -sS -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer test' "$RENAME_URL/api/cache/gradle/key?tenant_id=other&namespace_id=ios")" = 403 ] || return 1
    [ "$(curl -sS -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer test' "$RENAME_URL/api/cache/gradle/key?tenant_id=renamed&namespace_id=other")" = 403 ]
  }

  BeforeAll 'setup_rename'
  AfterAll 'teardown_rename'

  It 'refreshes authorization and retains old cache bytes without restarting'
    When call rename_roundtrip
    The status should be success
    The output should be blank
  End
End
