#!/bin/bash
# Extracts the cache staging functions from dispatch-poll.sh and runs them, and
# tuist-runner-cache, against temporary directories. Never mounts anything.
# shellcheck disable=SC2034
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }

eval "$(awk '/^(stage_runner_caches|runner_caches_used)\(\)/ {copy=1} copy {print} copy && /^}$/ {copy=0}' "$ROOT/dispatch-poll.sh")"
declare -F stage_runner_caches >/dev/null || fail 'stage_runner_caches missing'
declare -F runner_caches_used >/dev/null || fail 'runner_caches_used missing'
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT

setup() {
  work=$(mktemp -d "$base/test.XXXXXX")
  RUNNER_CACHES_DIR="$work/caches"
  STATUS_SHARE="$work/status"
  mkdir -p "$STATUS_SHARE"
  printf '{}' >"$STATUS_SHARE/cache-usage.json"
  CACHE_MOUNT="$work/mount"
  export TUIST_XDG_CACHE_HOME="$CACHE_MOUNT" TUIST_CACHE_MAX_BYTES=1000
  printf 'COMPILATION_CACHE_CAS_PATH = %s\n' "$CACHE_MOUNT/CompilationCache.noindex" >"$work/cas.xcconfig"
  export XCODE_XCCONFIG_FILE="$work/cas.xcconfig"
  export TUIST_COMPILATION_CACHE_CAS_PATH="$CACHE_MOUNT/CompilationCache.noindex"
  export TUIST_CAS_DRAINED_STORE="$CACHE_MOUNT/CompilationCache.noindex"
}
activate() { TUIST_RUNNER_CACHES_DIR="$RUNNER_CACHES_DIR" "$ROOT/tuist-runner-cache" activate "$@"; }

test_automatic_caches_keep_the_job_environment() {
  setup
  AUTOMATIC_CACHES=1
  stage_runner_caches >/dev/null
  eq automatic "$(cat "$RUNNER_CACHES_DIR/mode")"
  eq "$CACHE_MOUNT" "${TUIST_XDG_CACHE_HOME:-}"
  eq "$work/cas.xcconfig" "${XCODE_XCCONFIG_FILE:-}"
  [ -f "$STATUS_SHARE/cache-usage.json" ] || fail 'automatic caches dropped the usage sample'
  runner_caches_used || fail 'automatic caches read as unused'
  out=$(activate xcode 2>/dev/null) || fail 'activation failed on automatic caches'
  eq '' "$out"
}

test_opt_in_caches_move_the_environment_to_their_actions() {
  setup
  AUTOMATIC_CACHES=0
  stage_runner_caches >/dev/null
  eq opt-in "$(cat "$RUNNER_CACHES_DIR/mode")"
  for name in TUIST_XDG_CACHE_HOME TUIST_CACHE_MAX_BYTES XCODE_XCCONFIG_FILE TUIST_COMPILATION_CACHE_CAS_PATH TUIST_CAS_DRAINED_STORE; do
    [ -z "${!name:-}" ] || fail "$name still reaches the runner"
  done
  [ ! -e "$STATUS_SHARE/cache-usage.json" ] || fail 'unused job would be reported as a volume use'
  eq "TUIST_XDG_CACHE_HOME=$CACHE_MOUNT"$'\n'"TUIST_CACHE_MAX_BYTES=1000" "$(cat "$RUNNER_CACHES_DIR/module.env")"
  grep -qx "XCODE_XCCONFIG_FILE=$work/cas.xcconfig" "$RUNNER_CACHES_DIR/xcode.env" || fail 'xcconfig not staged'
  grep -qx "TUIST_CAS_DRAINED_STORE=$CACHE_MOUNT/CompilationCache.noindex" "$RUNNER_CACHES_DIR/xcode.env" || fail 'drained store not staged'
  runner_caches_used && fail 'opt-in caches read as used before activation'

  eq "$(cat "$RUNNER_CACHES_DIR/module.env")" "$(activate module 2>/dev/null)"
  runner_caches_used || fail 'activated module cache reads as unused'
  [ ! -e "$RUNNER_CACHES_DIR/xcode.used" ] || fail 'module activation marked the xcode cache'
}

test_xcode_activation_includes_the_workflow_xcconfig_last() {
  setup
  AUTOMATIC_CACHES=0
  stage_runner_caches >/dev/null
  printf 'SWIFT_VERSION = 6\n' >"$work/theirs.xcconfig"
  XCODE_XCCONFIG_FILE="$work/theirs.xcconfig" activate xcode >"$work/env" 2>/dev/null || fail 'xcode activation failed'
  XCODE_XCCONFIG_FILE="$work/theirs.xcconfig" activate xcode >/dev/null 2>&1 || fail 'repeated activation failed'
  eq "#include \"$work/theirs.xcconfig\"" "$(tail -n 1 "$work/cas.xcconfig")"
  eq 1 "$(grep -c '^#include' "$work/cas.xcconfig")"
  grep -qx "XCODE_XCCONFIG_FILE=$work/cas.xcconfig" "$work/env" || fail 'activation does not export the runner xcconfig'
  [ -e "$RUNNER_CACHES_DIR/xcode.used" ] || fail 'xcode activation not recorded'
}

test_unavailable_caches_warn_without_exporting() {
  setup
  AUTOMATIC_CACHES=0
  CACHE_MOUNT=""
  unset TUIST_COMPILATION_CACHE_CAS_PATH
  stage_runner_caches >/dev/null
  status=0
  out=$(activate xcode 2>"$work/err") || status=$?
  eq 3 "$status"
  eq '' "$out"
  grep -q 'unavailable' "$work/err" || fail 'no explanation for the empty cache'
  runner_caches_used && fail 'unavailable cache read as used'
}

test_other_runners_are_left_alone() {
  setup
  status=0
  out=$(activate module 2>"$work/err") || status=$?
  eq 0 "$status"
  eq '' "$out"
  grep -q 'does not provide' "$work/err" || fail 'no explanation on a runner without caches'
  status=0
  activate gradle >/dev/null 2>&1 || status=$?
  eq 2 "$status"
}

for test in $(declare -F | awk '{print $3}' | grep '^test_'); do
  "$test"
  echo "ok: $test"
done
