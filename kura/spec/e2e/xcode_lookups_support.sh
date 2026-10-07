# shellcheck shell=bash

# Milliseconds the gate holds every action lookup, standing in for a distant cache.
LOOKUP_TEST_DELAY_MS=200

setup_xcode_lookups() {
  xcode_chunking_enabled || return 0
  LOOKUP_TEST_URL="${TUIST_CHUNKING_TEST_URL:-http://127.0.0.1:18765}"
  [[ "$LOOKUP_TEST_URL" =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || return 1
  curl --fail --silent --max-time 5 "$LOOKUP_TEST_URL/ready" >/dev/null || return 1
  LOOKUP_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kura-lookups.XXXXXX")"
  LOOKUP_TEST_ROOT="$(cd "$LOOKUP_TEST_ROOT" && pwd -P)"
  LOOKUP_TEST_SOCKET="$LOOKUP_TEST_ROOT/proxy.sock"
  LOOKUP_TEST_DERIVED="$LOOKUP_TEST_ROOT/DerivedData"
  local release_bin="$KURA_PROJECT_ROOT/../cas-plugin/target/release"
  local plugin_bin="${KURA_E2E_CAS_BIN:-$release_bin}"
  mkdir "$LOOKUP_TEST_ROOT/bin" || return 1
  cp "$plugin_bin/libtuist_cas_plugin.dylib" "$plugin_bin/tuist-cas-proxy" \
    "$release_bin/examples/chunking_fault_gate" "$LOOKUP_TEST_ROOT/bin/" || return 1
  cp "$KURA_PROJECT_ROOT/spec/fixtures/xcode-lookups/Project.swift" \
    "$KURA_PROJECT_ROOT/spec/fixtures/xcode-lookups/Tuist.swift" \
    "$KURA_PROJECT_ROOT/spec/fixtures/xcode-lookups/Fixture.swift" "$LOOKUP_TEST_ROOT/" || return 1
  tuist generate --path "$LOOKUP_TEST_ROOT" --no-open --cache-profile none >"$LOOKUP_TEST_ROOT/generate.log" 2>&1 || {
    cat "$LOOKUP_TEST_ROOT/generate.log" >&2
    return 1
  }
}

stop_lookup_processes() {
  local pid
  for pid in "${LOOKUP_TEST_PROXY_PID:-}" "${LOOKUP_TEST_GATE_PID:-}"; do
    [ -n "$pid" ] || continue
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  LOOKUP_TEST_PROXY_PID=""
  LOOKUP_TEST_GATE_PID=""
  [ -z "${LOOKUP_TEST_SOCKET:-}" ] || rm -f "$LOOKUP_TEST_SOCKET"
}

teardown_xcode_lookups() {
  stop_lookup_processes
  [ -z "${LOOKUP_TEST_ROOT:-}" ] || printf 'Xcode evidence: %s\n' "$LOOKUP_TEST_ROOT"
}

# Builds the fixture into an empty compiler store, through a fresh proxy whose
# remote is the gate in front of Kura. `namespace` selects the Kura namespace,
# so a phase only finds what an earlier phase of the same namespace uploaded.
run_lookup_phase() {
  local phase="$1" namespace="$2" upload="$3" mode="$4" _attempt control="$LOOKUP_TEST_ROOT/$1-control"
  local instance
  instance="chunking-test/$(basename "$LOOKUP_TEST_ROOT")-$namespace"
  mkdir -p "$control" "$LOOKUP_TEST_ROOT/$phase-reader" || return 1
  printf '%s\n' "$mode" >"$control/mode"
  "$LOOKUP_TEST_ROOT/bin/chunking_fault_gate" "$LOOKUP_TEST_URL" "$control" >"$control/server.log" 2>&1 &
  LOOKUP_TEST_GATE_PID=$!
  for _attempt in $(seq 1 100); do
    [ ! -s "$control/address" ] || break
    kill -0 "$LOOKUP_TEST_GATE_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  [ -s "$control/address" ] || return 1
  env TUIST_CAS_PROXY_SOCKET="$LOOKUP_TEST_SOCKET" \
    TUIST_CAS_PROXY_REGISTRY="$LOOKUP_TEST_ROOT/$phase-reader/registry" \
    TUIST_CAS_REMOTE_GRPC_URL="$(cat "$control/address")" TUIST_CAS_TOKEN=local-fixture \
    TUIST_CAS_PREFETCH=0 TUIST_CAS_TUIST_BIN=/usr/bin/false TUIST_CAS_ANALYTICS_DB= \
    TUIST_CAS_UPLOAD="$upload" TUIST_CAS_LOG="$LOOKUP_TEST_ROOT/$phase.proxy.log" \
    "$LOOKUP_TEST_ROOT/bin/tuist-cas-proxy" >"$LOOKUP_TEST_ROOT/$phase.proxy-stdout.log" 2>&1 &
  LOOKUP_TEST_PROXY_PID=$!
  for _attempt in $(seq 1 100); do
    [ ! -S "$LOOKUP_TEST_SOCKET" ] || break
    kill -0 "$LOOKUP_TEST_PROXY_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  [ -S "$LOOKUP_TEST_SOCKET" ] || return 1
  env TUIST_CAS_PROXY_SOCKET="$LOOKUP_TEST_SOCKET" TUIST_CAS_UPLOAD="$upload" \
    TUIST_CAS_LOG="$LOOKUP_TEST_ROOT/$phase.plugin.log" \
    xcodebuild build -workspace "$LOOKUP_TEST_ROOT/LookupFixture.xcworkspace" -scheme LookupFixture \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$LOOKUP_TEST_DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    "TUIST_XCODE_TEST_PLUGIN=$LOOKUP_TEST_ROOT/bin/libtuist_cas_plugin.dylib" \
    "TUIST_XCODE_TEST_SOCKET=$LOOKUP_TEST_SOCKET" "TUIST_XCODE_TEST_INSTANCE=$instance" \
    >"$LOOKUP_TEST_ROOT/$phase.build.log" 2>&1 || {
      stop_lookup_processes
      return 1
    }
  if [ "$upload" = true ]; then
    local store_path
    store_path="$(cut -f1 "$LOOKUP_TEST_ROOT/$phase-reader/registry")" || return 1
    "$LOOKUP_TEST_ROOT/bin/tuist-cas-proxy" --drain "$store_path" \
      --socket "$LOOKUP_TEST_SOCKET" --timeout-ms 60000 >"$LOOKUP_TEST_ROOT/$phase.drain.log" 2>&1 || return 1
  fi
  stop_lookup_processes
  mv "$LOOKUP_TEST_DERIVED" "$LOOKUP_TEST_ROOT/$phase" || return 1
}

# The most action lookups the gate held at the same time during a phase.
lookup_concurrency() {
  awk '{ print $1, 1; print $2, -1 }' "$LOOKUP_TEST_ROOT/$1-control/lookups" |
    sort -k1,1n -k2,2n |
    awk '{ current += $2; if (current > peak) peak = current } END { print peak + 0 }'
}

lookup_count() {
  wc -l <"$LOOKUP_TEST_ROOT/$1-control/lookups" | tr -d ' '
}

lookup_hits() {
  sed -nE 's/^note: ([0-9]+) hits? \/ ([0-9]+) cacheable tasks?.*/\1\/\2/p' "$LOOKUP_TEST_ROOT/$1.build.log" | tail -1
}

# Holds every action lookup of a phase for the delay below.
delayed_lookups() { printf 'delay-lookups=%s' "$LOOKUP_TEST_DELAY_MS"; }

lookup_tasks() {
  lookup_hits "$1" | cut -d/ -f2
}

lookup_at_least() { [ "${lookup_at_least:?}" -ge "$1" ]; }
