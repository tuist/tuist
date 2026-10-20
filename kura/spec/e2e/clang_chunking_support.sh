# shellcheck shell=bash

setup_clang_chunking() {
  xcode_chunking_enabled || return 0
  CLANG_TEST_URL="${TUIST_CHUNKING_TEST_URL:-http://127.0.0.1:18765}"
  [[ "$CLANG_TEST_URL" =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || return 1
  curl --fail --silent --max-time 5 "$CLANG_TEST_URL/up" >/dev/null || return 1
  CLANG_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kura-clang.XXXXXX")"
  CLANG_TEST_ROOT="$(cd "$CLANG_TEST_ROOT" && pwd -P)"
  CLANG_TEST_SOCKET="$CLANG_TEST_ROOT/proxy.sock"
  CLANG_TEST_DERIVED="$CLANG_TEST_ROOT/DerivedData"
  local release_bin="$KURA_PROJECT_ROOT/../cas-plugin/target/release"
  local plugin_bin="${KURA_E2E_CAS_BIN:-$release_bin}"
  mkdir "$CLANG_TEST_ROOT/bin" || return 1
  cp "$plugin_bin/libtuist_cas_plugin.dylib" "$plugin_bin/tuist-cas-proxy" \
    "$release_bin/examples/chunking_fault_gate" "$CLANG_TEST_ROOT/bin/" || return 1
  cp "$KURA_PROJECT_ROOT/spec/fixtures/clang-chunking/Project.swift" \
    "$KURA_PROJECT_ROOT/spec/fixtures/clang-chunking/Tuist.swift" "$CLANG_TEST_ROOT/" || return 1
  awk -f "$KURA_PROJECT_ROOT/spec/fixtures/clang-chunking/data.awk" >"$CLANG_TEST_ROOT/Fixture.c" || return 1
  tuist generate --path "$CLANG_TEST_ROOT" --no-open --cache-profile none >"$CLANG_TEST_ROOT/generate.log" 2>&1 || return 1
}

stop_clang_proxy() {
  if [ -f "${CLANG_TEST_ROOT:-}/proxy.pid" ]; then
    CLANG_TEST_PROXY_PID="$(cat "$CLANG_TEST_ROOT/proxy.pid")"
  fi
  if [ -n "${CLANG_TEST_PROXY_PID:-}" ]; then
    kill "$CLANG_TEST_PROXY_PID" 2>/dev/null || true
    wait "$CLANG_TEST_PROXY_PID" 2>/dev/null || true
    CLANG_TEST_PROXY_PID=""
    rm -f "$CLANG_TEST_ROOT/proxy.pid" "$CLANG_TEST_SOCKET"
  fi
}

stop_clang_gate() {
  stop_clang_proxy
  if [ -f "${CLANG_TEST_ROOT:-}/gate.pid" ]; then
    CLANG_TEST_GATE_PID="$(cat "$CLANG_TEST_ROOT/gate.pid")"
  fi
  if [ -n "${CLANG_TEST_GATE_PID:-}" ]; then
    kill "$CLANG_TEST_GATE_PID" 2>/dev/null || true
    wait "$CLANG_TEST_GATE_PID" 2>/dev/null || true
    CLANG_TEST_GATE_PID=""
    rm -f "$CLANG_TEST_ROOT/gate.pid"
  fi
  if [ -d "${CLANG_TEST_DERIVED:-}" ]; then
    mv "$CLANG_TEST_DERIVED" "$CLANG_TEST_ROOT/unfinished-$(date +%s)"
  fi
}

teardown_clang_chunking() {
  stop_clang_gate
  [ -z "${CLANG_TEST_ROOT:-}" ] || printf 'Clang evidence: %s\n' "$CLANG_TEST_ROOT"
}

start_clang_gate() {
  local name="$1" mode="$2" _attempt
  CLANG_TEST_CONTROL="$CLANG_TEST_ROOT/$name-control"
  CLANG_TEST_INSTANCE="chunking-test/$(basename "$CLANG_TEST_ROOT")-$name"
  mkdir "$CLANG_TEST_CONTROL" || return 1
  printf '%s\n' "$mode" >"$CLANG_TEST_CONTROL/mode"
  "$CLANG_TEST_ROOT/bin/chunking_fault_gate" "$CLANG_TEST_URL" "$CLANG_TEST_CONTROL" \
    >"$CLANG_TEST_CONTROL/server.log" 2>&1 &
  CLANG_TEST_GATE_PID=$!
  printf '%s\n' "$CLANG_TEST_GATE_PID" >"$CLANG_TEST_ROOT/gate.pid"
  for _attempt in $(seq 1 100); do
    [ ! -s "$CLANG_TEST_CONTROL/address" ] || return 0
    kill -0 "$CLANG_TEST_GATE_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

start_clang_proxy() {
  local phase="$1" _attempt
  mkdir -p "$CLANG_TEST_ROOT/$phase-reader" || return 1
  env TUIST_CAS_PROXY_SOCKET="$CLANG_TEST_SOCKET" \
    TUIST_CAS_PROXY_REGISTRY="$CLANG_TEST_ROOT/$phase-reader/registry" \
    TUIST_CAS_REMOTE_GRPC_URL="$(cat "$CLANG_TEST_CONTROL/address")" \
    TUIST_CAS_TOKEN=local-fixture TUIST_CAS_PREFETCH=0 \
    TUIST_CAS_TUIST_BIN=/usr/bin/false TUIST_CAS_ANALYTICS_DB= \
    TUIST_CAS_LOG="$CLANG_TEST_ROOT/$phase.proxy.log" \
    "$CLANG_TEST_ROOT/bin/tuist-cas-proxy" >"$CLANG_TEST_ROOT/$phase.proxy-stdout.log" 2>&1 &
  CLANG_TEST_PROXY_PID=$!
  printf '%s\n' "$CLANG_TEST_PROXY_PID" >"$CLANG_TEST_ROOT/proxy.pid"
  for _attempt in $(seq 1 100); do
    [ ! -S "$CLANG_TEST_SOCKET" ] || return 0
    kill -0 "$CLANG_TEST_PROXY_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

build_clang_fixture() {
  local phase="$1" upload="$2"
  env TUIST_CAS_PROXY_SOCKET="$CLANG_TEST_SOCKET" TUIST_CAS_UPLOAD="$upload" \
    TUIST_CAS_ACCOUNT=chunking-test TUIST_CAS_PROJECT="${CLANG_TEST_INSTANCE#chunking-test/}" \
    TUIST_CAS_LOG="$CLANG_TEST_ROOT/$phase.plugin.log" \
    xcodebuild build -workspace "$CLANG_TEST_ROOT/ClangChunkFixture.xcworkspace" -scheme ClangChunkFixture \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$CLANG_TEST_DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    "TUIST_XCODE_TEST_PLUGIN=$CLANG_TEST_ROOT/bin/libtuist_cas_plugin.dylib" \
    "TUIST_XCODE_TEST_SOCKET=$CLANG_TEST_SOCKET" "TUIST_XCODE_TEST_INSTANCE=$CLANG_TEST_INSTANCE" \
    >"$CLANG_TEST_ROOT/$phase.build.log" 2>&1
}

drain_clang_upload() {
  local phase="$1" store_path
  store_path="$(cut -f1 "$CLANG_TEST_ROOT/$phase-reader/registry")" || return 1
  "$CLANG_TEST_ROOT/bin/tuist-cas-proxy" --drain "$store_path" \
    --socket "$CLANG_TEST_SOCKET" --timeout-ms 5000 >"$CLANG_TEST_ROOT/$phase.drain.log" 2>&1
}

finish_clang_phase() {
  stop_clang_proxy
  mv "$CLANG_TEST_DERIVED" "$CLANG_TEST_ROOT/$1" || return 1
}

clang_hits() {
  sed -nE 's/.*([0-9]+) hits? \/ ([0-9]+) cacheable tasks?.*/\1\/\2/p' "$CLANG_TEST_ROOT/$1.build.log" | tail -1
}

compare_clang_output() {
  local object='Build/Intermediates.noindex/ClangChunkFixture.build/Debug/ClangChunkFixture.build/Objects-normal/arm64/Fixture.o'
  cmp "$CLANG_TEST_ROOT/$1/$object" "$CLANG_TEST_ROOT/$2/$object"
}

evict_during_clang_restore() {
  local phase="$1" build_pid _attempt waiting=0 result=0
  printf 'hold-chunks\n' >"$CLANG_TEST_CONTROL/mode"
  start_clang_proxy "$phase" || return 1
  build_clang_fixture "$phase" true &
  build_pid=$!
  for _attempt in $(seq 1 400); do
    if [ -f "$CLANG_TEST_CONTROL/chunk-read-held" ]; then waiting=1; break; fi
    sleep 0.1
  done
  if [ "$waiting" = 1 ]; then
    # This namespace belongs only to this test. The server has returned an
    # action and recipe, but no chunk read can finish until after deletion.
    curl --fail --silent --max-time 10 -X DELETE --get \
      --data-urlencode 'tenant_id=chunking-test' \
      --data-urlencode "namespace_id=${CLANG_TEST_INSTANCE#chunking-test/}" \
      "$CLANG_TEST_URL/api/cache/clean" >/dev/null || result=1
  else
    result=1
  fi
  touch "$CLANG_TEST_CONTROL/release"
  wait "$build_pid" || result=1
  # The compiler may finish before the background read reports the loss.
  for _attempt in $(seq 1 100); do
    if rg -q '^whole-missing$' "$CLANG_TEST_CONTROL/events"; then break; fi
    sleep 0.1
  done
  drain_clang_upload "$phase" || result=1
  finish_clang_phase "$phase" || return 1
  return "$result"
}
