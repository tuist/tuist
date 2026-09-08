# shellcheck shell=bash

xcode_chunking_enabled() {
  [ "${KURA_E2E_XCODE:-0}" = "1" ] && [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]
}

xcode_chunking_disabled() { ! xcode_chunking_enabled; }

setup_xcode_chunking() {
  xcode_chunking_enabled || return 0
  XCODE_TEST_URL="${TUIST_CHUNKING_TEST_URL:-http://127.0.0.1:18765}"
  [[ "$XCODE_TEST_URL" =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || return 1
  curl --fail --silent --max-time 5 "$XCODE_TEST_URL/up" >/dev/null || return 1
  XCODE_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kura-xcode.XXXXXX")"
  XCODE_TEST_ROOT="$(cd "$XCODE_TEST_ROOT" && pwd -P)"
  local release_bin="${KURA_PROJECT_ROOT}/../cas-plugin/target/release"
  [ -f "$release_bin/libtuist_cas_plugin.dylib" ] && [ -x "$release_bin/tuist-cas-proxy" ] || return 1
  # Keep every phase on the same binaries even if another build runs locally.
  XCODE_TEST_BIN="$XCODE_TEST_ROOT/bin"
  mkdir -p "$XCODE_TEST_BIN" || return 1
  cp "$release_bin/libtuist_cas_plugin.dylib" "$release_bin/tuist-cas-proxy" "$XCODE_TEST_BIN/" || return 1
  XCODE_TEST_SOCKET="$XCODE_TEST_ROOT/proxy.sock"
  XCODE_TEST_DERIVED="$XCODE_TEST_ROOT/DerivedData"
  XCODE_TEST_INSTANCE="chunking-test/$(basename "$XCODE_TEST_ROOT")"
  cp "$KURA_PROJECT_ROOT/spec/fixtures/xcode-chunking/project.yml" "$XCODE_TEST_ROOT/project.yml" || return 1
  awk -f "$KURA_PROJECT_ROOT/spec/fixtures/xcode-chunking/declarations.awk" >"$XCODE_TEST_ROOT/base.swift" || return 1
  awk -v rename_property=1 -f "$KURA_PROJECT_ROOT/spec/fixtures/xcode-chunking/declarations.awk" >"$XCODE_TEST_ROOT/edited.swift" || return 1
  cp "$XCODE_TEST_ROOT/base.swift" "$XCODE_TEST_ROOT/Fixture.swift" || return 1
  (cd "$XCODE_TEST_ROOT" && mise x xcodegen@2.46.0 -- xcodegen generate) >"$XCODE_TEST_ROOT/generate.log" 2>&1 || return 1
  run_xcode_phase base-compiled base writer true || return 1
  run_xcode_phase edited-compiled edited writer true || return 1
  [ "$(xcode_hits base-compiled)" = "0/4" ] || return 1
  [ "$(xcode_hits edited-compiled)" = "2/4" ] || return 1
}

stop_xcode_proxy() {
  if [ -n "${XCODE_TEST_PROXY_PID:-}" ]; then
    kill "$XCODE_TEST_PROXY_PID" 2>/dev/null || true
    wait "$XCODE_TEST_PROXY_PID" 2>/dev/null || true
    XCODE_TEST_PROXY_PID=""
  fi
  if [ -n "${XCODE_TEST_SOCKET:-}" ]; then
    rm -f "$XCODE_TEST_SOCKET"
  fi
}

teardown_xcode_chunking() {
  stop_xcode_proxy
  # Retain the isolated fixture, compiler stores, and logs for inspection.
  if [ -n "${XCODE_TEST_ROOT:-}" ]; then
    printf 'Xcode evidence: %s\n' "$XCODE_TEST_ROOT"
  fi
}

run_xcode_phase() {
  local phase="$1" revision="$2" reader="$3" upload="$4" _attempt
  local build_status=0
  cp "$XCODE_TEST_ROOT/$revision.swift" "$XCODE_TEST_ROOT/Fixture.swift" || return 1
  mkdir -p "$XCODE_TEST_ROOT/$reader" || return 1
  env TUIST_CAS_PROXY_SOCKET="$XCODE_TEST_SOCKET" \
    TUIST_CAS_PROXY_REGISTRY="$XCODE_TEST_ROOT/$reader/registry" \
    TUIST_CAS_REMOTE_GRPC_URL="$XCODE_TEST_URL" TUIST_CAS_TOKEN=local-fixture \
    TUIST_CAS_PREFETCH=0 TUIST_CAS_TUIST_BIN=/usr/bin/false TUIST_CAS_ANALYTICS_DB= \
    TUIST_CAS_UPLOAD="$upload" TUIST_CAS_LOG="$XCODE_TEST_ROOT/$phase.proxy.log" \
    "$XCODE_TEST_BIN/tuist-cas-proxy" >"$XCODE_TEST_ROOT/$phase.proxy-stdout.log" 2>&1 &
  XCODE_TEST_PROXY_PID=$!
  for _attempt in $(seq 1 100); do
    [ -S "$XCODE_TEST_SOCKET" ] && break
    kill -0 "$XCODE_TEST_PROXY_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  [ -S "$XCODE_TEST_SOCKET" ] || return 1
  env TUIST_CAS_PROXY_SOCKET="$XCODE_TEST_SOCKET" TUIST_CAS_UPLOAD="$upload" \
    TUIST_CAS_LOG="$XCODE_TEST_ROOT/$phase.plugin.log" \
    xcodebuild build -project "$XCODE_TEST_ROOT/SwiftChunkFixture.xcodeproj" -scheme SwiftChunkFixture \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$XCODE_TEST_DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    "TUIST_XCODE_TEST_PLUGIN=$XCODE_TEST_BIN/libtuist_cas_plugin.dylib" \
    "TUIST_XCODE_TEST_SOCKET=$XCODE_TEST_SOCKET" "TUIST_XCODE_TEST_INSTANCE=$XCODE_TEST_INSTANCE" \
    >"$XCODE_TEST_ROOT/$phase.build.log" 2>&1 || build_status=$?
  if [ "$build_status" != 0 ]; then
    stop_xcode_proxy
    return "$build_status"
  fi
  if [ "$upload" = true ]; then
    # Xcode can spell /private/var as /var. Drain the path it actually registered.
    local store_path
    store_path="$(cut -f1 "$XCODE_TEST_ROOT/$reader/registry")" || return 1
    [ -d "$store_path" ] || return 1
    "$XCODE_TEST_BIN/tuist-cas-proxy" --drain "$store_path" \
      --socket "$XCODE_TEST_SOCKET" --timeout-ms 30000 >"$XCODE_TEST_ROOT/$phase.drain.log" 2>&1 || {
        cat "$XCODE_TEST_ROOT/$phase.drain.log" >&2
        return 1
      }
  else
    # Wait for a stats line newer than the completed build, not a startup sample.
    local finished_seconds received=0
    finished_seconds="$(date +%s)"
    for _attempt in $(seq 1 120); do
      if awk -v finished="$finished_seconds" '/proxy stats:/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^t=/) {
          time = $i; sub(/^t=/, "", time)
          if (time >= (finished + 1) * 1000) found = 1
        }
      } END { exit !found }' "$XCODE_TEST_ROOT/$phase.proxy.log"; then
        received=1
        break
      fi
      sleep 0.1
    done
    [ "$received" = 1 ] || return 1
  fi
  stop_xcode_proxy
  mv "$XCODE_TEST_DERIVED" "$XCODE_TEST_ROOT/$phase" || return 1
}

xcode_hits() {
  sed -nE 's/.*([0-9]+) hits \/ ([0-9]+) cacheable tasks.*/\1\/\2/p' "$XCODE_TEST_ROOT/$1.build.log" | tail -1
}

xcode_counter() {
  awk -v key="$2" '/proxy stats:/ {
    for (i = 1; i <= NF; i++) if (index($i, key "=") == 1) { value = $i; sub(/^[^=]*=/, "", value) }
  } END { if (value == "") exit 1; print value }' "$XCODE_TEST_ROOT/$1.proxy.log"
}

compare_xcode_outputs() {
  local expected="$1" actual="$2" name
  local objects='Build/Intermediates.noindex/SwiftChunkFixture.build/Debug/SwiftChunkFixture.build/Objects-normal/arm64'
  for name in SwiftChunkFixture.swiftmodule Fixture.o Fixture.swiftdeps \
    SwiftChunkFixture.swiftsourceinfo SwiftChunkFixture.swiftdoc SwiftChunkFixture-Swift.h \
    SwiftChunkFixture.abi.json Fixture.swiftconstvalues Fixture.d Fixture.dia \
    SwiftChunkFixture-primary-emit-module.d SwiftChunkFixture-primary-emit-module.dia; do
    cmp "$XCODE_TEST_ROOT/$expected/$objects/$name" "$XCODE_TEST_ROOT/$actual/$objects/$name" || return 1
  done
}

xcode_greater_than() { [ "${xcode_greater_than:?}" -gt "$1" ]; }
xcode_less_than() { [ "${xcode_less_than:?}" -lt "$1" ]; }
