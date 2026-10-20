#!/bin/bash
# Extracts the cache staging functions from dispatch-poll.sh and runs them, and
# tuist-runner-cache, against temporary directories. Never mounts anything.
# shellcheck disable=SC2034
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }

eval "$(awk '/^(stage_runner_caches|stage_managed_cache_volumes|cas_store_root|cas_spool_dirs|cas_store_dirs|runner_caches_used|cache_passed|report_cache_dirty)\(\)/ {copy=1} copy {print} copy && /^}$/ {copy=0}' "$ROOT/dispatch-poll.sh")"
declare -F stage_runner_caches >/dev/null || fail 'stage_runner_caches missing'
declare -F runner_caches_used >/dev/null || fail 'runner_caches_used missing'
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT

setup() {
  work=$(mktemp -d "$base/test.XXXXXX")
  RUNNER_CACHES_DIR="$work/caches"
  MANAGED_CACHE_VOLUMES=0
  CAS_STORE_ROOT=""
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

test_xcode_activation_resolves_a_relative_workflow_xcconfig() {
  setup
  AUTOMATIC_CACHES=0
  stage_runner_caches >/dev/null
  mkdir -p "$work/workspace/Config"
  printf 'SWIFT_VERSION = 6\n' >"$work/workspace/Config/CI.xcconfig"
  (cd "$work/workspace" && XCODE_XCCONFIG_FILE=Config/CI.xcconfig activate xcode >/dev/null 2>&1) || fail 'xcode activation failed'
  eq "#include \"$work/workspace/Config/CI.xcconfig\"" "$(tail -n 1 "$work/cas.xcconfig")"
}

test_staging_failure_keeps_the_caches_automatic() {
  setup
  AUTOMATIC_CACHES=0
  printf 'not a directory' >"$work/caches"
  stage_runner_caches >/dev/null
  eq 1 "$AUTOMATIC_CACHES"
  eq "$CACHE_MOUNT" "${TUIST_XDG_CACHE_HOME:-}"
  [ -f "$STATUS_SHARE/cache-usage.json" ] || fail 'staging failure dropped the usage sample'
  runner_caches_used || fail 'caches the job inherited read as unused'
}

test_only_a_successful_job_that_reached_the_caches_promotes() {
  setup
  AUTOMATIC_CACHES=0
  stage_runner_caches >/dev/null
  JOB_PASSED=1
  eq 0 "$(cache_passed)"
  activate module >/dev/null 2>&1
  eq 1 "$(cache_passed)"
  JOB_PASSED=0
  eq 0 "$(cache_passed)"
  AUTOMATIC_CACHES=1
  rm -f "$RUNNER_CACHES_DIR/module.used"
  JOB_PASSED=1
  eq 1 "$(cache_passed)"
}

test_unused_caches_are_reported_clean() {
  setup
  JOB_RESULT=succeeded
  CACHE_INVENTORY_BEFORE=before
  CACHE_INVENTORY_AFTER=after
  report_cache_dirty 0 >/dev/null
  eq 0 "$(cat "$STATUS_SHARE/cache-dirty")"
  report_cache_dirty 1 >/dev/null
  eq 1 "$(cat "$STATUS_SHARE/cache-dirty")"
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

managed_setup() {
  setup
  AUTOMATIC_CACHES=0
  MANAGED_CACHE_VOLUMES=1
  CACHE_MOUNT=""
  MANAGED_XCODE_CACHE="$work/xcode-cache"
  MANAGED_MODULE_CACHE="$work/module-cache"
  MANAGED_XCCONFIG="$work/managed.xcconfig"
  MANAGED_XCODE_CACHE_LIMIT_BYTES=24000000000
  MANAGED_MODULE_CACHE_MAX_BYTES=16000000000
  # A stand-in for the volume client: records each attach and creates the path.
  mkdir -p "$work/bin"
  cat >"$work/bin/tuist-cache-volume" <<EOF
#!/bin/bash
echo "\$*" >>"$work/attached"
[ "\$4" = "$work/broken" ] && exit 1
mkdir -p "\$4"
EOF
  chmod +x "$work/bin/tuist-cache-volume"
}

test_managed_caches_stage_their_volumes() {
  managed_setup
  stage_runner_caches >/dev/null
  eq opt-in "$(cat "$RUNNER_CACHES_DIR/mode")"
  eq "tuist-xcode"$'\t'"$MANAGED_XCODE_CACHE" "$(cat "$RUNNER_CACHES_DIR/xcode.volume")"
  eq "tuist-module"$'\t'"$MANAGED_MODULE_CACHE" "$(cat "$RUNNER_CACHES_DIR/module.volume")"
  eq "TUIST_XDG_CACHE_HOME=$MANAGED_MODULE_CACHE"$'\n'"TUIST_CACHE_MAX_BYTES=16000000000" "$(cat "$RUNNER_CACHES_DIR/module.env")"
  grep -qx "XCODE_XCCONFIG_FILE=$MANAGED_XCCONFIG" "$RUNNER_CACHES_DIR/xcode.env" || fail 'managed xcconfig not staged'
  grep -qx "TUIST_COMPILATION_CACHE_CAS_PATH=$MANAGED_XCODE_CACHE" "$RUNNER_CACHES_DIR/xcode.env" || fail 'store not staged'
  grep -qx "TUIST_CAS_DRAINED_STORE=$MANAGED_XCODE_CACHE" "$RUNNER_CACHES_DIR/xcode.env" || fail 'drained store not staged'
  grep -qx "COMPILATION_CACHE_CAS_PATH = $MANAGED_XCODE_CACHE" "$MANAGED_XCCONFIG" || fail 'xcconfig does not point at the volume'
  grep -qx "COMPILATION_CACHE_LIMIT_SIZE = 24000000000" "$MANAGED_XCCONFIG" || fail 'xcconfig does not bound the store'
  for name in TUIST_XDG_CACHE_HOME TUIST_CACHE_MAX_BYTES XCODE_XCCONFIG_FILE TUIST_COMPILATION_CACHE_CAS_PATH TUIST_CAS_DRAINED_STORE; do
    [ -z "${!name:-}" ] || fail "$name still reaches the runner"
  done
  [ ! -e "$STATUS_SHARE/cache-usage.json" ] || fail 'a managed job reported built-in volume usage'
}

test_managed_activation_attaches_the_volume_once() {
  managed_setup
  stage_runner_caches >/dev/null
  out=$(PATH="$work/bin:$PATH" activate xcode 2>/dev/null) || fail 'managed xcode activation failed'
  PATH="$work/bin:$PATH" activate xcode >/dev/null 2>&1 || fail 'repeated managed activation failed'
  eq "$(cat "$RUNNER_CACHES_DIR/xcode.env")" "$out"
  eq "--key tuist-xcode --path $MANAGED_XCODE_CACHE" "$(cat "$work/attached")"
  [ -d "$MANAGED_XCODE_CACHE" ] || fail 'volume not attached at the store path'
  [ -e "$RUNNER_CACHES_DIR/xcode.used" ] || fail 'managed activation not recorded'
}

test_managed_activation_exports_nothing_when_the_volume_cannot_attach() {
  managed_setup
  MANAGED_MODULE_CACHE="$work/broken"
  stage_runner_caches >/dev/null
  status=0
  out=$(PATH="$work/bin:$PATH" activate module 2>"$work/err") || status=$?
  eq 3 "$status"
  eq '' "$out"
  grep -q 'empty cache' "$work/err" || fail 'no explanation when the volume cannot attach'
}

test_compilation_cache_stores_follow_the_managed_store_root() {
  managed_setup
  mkdir -p "$work/volume/data/plugin/v1.1" "$work/volume/data/plugin/tuist-spool"
  ln -s "$work/volume/data" "$MANAGED_XCODE_CACHE"
  CAS_STORE_ROOT="$MANAGED_XCODE_CACHE"
  eq "$MANAGED_XCODE_CACHE/plugin/tuist-spool" "$(cas_spool_dirs)"
  eq "$MANAGED_XCODE_CACHE/plugin" "$(cas_store_dirs)"
  CAS_STORE_ROOT=""
  eq '' "$(cas_spool_dirs)"
}

for test in $(declare -F | awk '{print $3}' | grep '^test_'); do
  "$test"
  echo "ok: $test"
done
