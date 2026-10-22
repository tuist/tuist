#!/bin/bash
# Extracts the cache staging functions from dispatch-poll.sh and runs them, and
# tuist-runner-cache, against temporary directories. Never mounts anything.
# shellcheck disable=SC2034
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }

eval "$(awk '/^(stage_runner_caches|stage_managed_cache_volumes|cas_store_root|cas_spool_dirs|cas_store_dirs)\(\)/ {copy=1} copy {print} copy && /^}$/ {copy=0}' "$ROOT/dispatch-poll.sh")"
for function in stage_runner_caches stage_managed_cache_volumes cas_store_root cas_spool_dirs cas_store_dirs; do
  declare -F "$function" >/dev/null || fail "$function missing"
done
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT

setup() {
  work=$(mktemp -d "$base/test.XXXXXX")
  RUNNER_CACHES_DIR="$work/caches"
  CAS_STORE_ROOT=""
  MANAGED_XCODE_CACHE="$work/xcode-cache"
  MANAGED_MODULE_CACHE="$work/module-cache"
  MANAGED_XCCONFIG="$work/managed.xcconfig"
  MANAGED_XCODE_CACHE_LIMIT_BYTES=24000000000
  MANAGED_MODULE_CACHE_MAX_BYTES=16000000000
  unset TUIST_XDG_CACHE_HOME TUIST_CACHE_MAX_BYTES XCODE_XCCONFIG_FILE \
    TUIST_COMPILATION_CACHE_CAS_PATH TUIST_CAS_DRAINED_STORE
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
activate() { TUIST_RUNNER_CACHES_DIR="$RUNNER_CACHES_DIR" PATH="$work/bin:$PATH" "$ROOT/tuist-runner-cache" activate "$@"; }

test_caches_stage_their_volumes() {
  setup
  stage_runner_caches >/dev/null
  eq opt-in "$(cat "$RUNNER_CACHES_DIR/mode")"
  eq "tuist-xcode"$'\t'"$MANAGED_XCODE_CACHE" "$(cat "$RUNNER_CACHES_DIR/xcode.volume")"
  eq "tuist-module"$'\t'"$MANAGED_MODULE_CACHE" "$(cat "$RUNNER_CACHES_DIR/module.volume")"
  eq "TUIST_XDG_CACHE_HOME=$MANAGED_MODULE_CACHE"$'\n'"TUIST_CACHE_MAX_BYTES=16000000000" "$(cat "$RUNNER_CACHES_DIR/module.env")"
  grep -qx "XCODE_XCCONFIG_FILE=$MANAGED_XCCONFIG" "$RUNNER_CACHES_DIR/xcode.env" || fail 'xcconfig not staged'
  grep -qx "TUIST_COMPILATION_CACHE_CAS_PATH=$MANAGED_XCODE_CACHE" "$RUNNER_CACHES_DIR/xcode.env" || fail 'store not staged'
  grep -qx "TUIST_CAS_DRAINED_STORE=$MANAGED_XCODE_CACHE" "$RUNNER_CACHES_DIR/xcode.env" || fail 'drained store not staged'
  grep -qx "COMPILATION_CACHE_CAS_PATH = $MANAGED_XCODE_CACHE" "$MANAGED_XCCONFIG" || fail 'xcconfig does not point at the volume'
  grep -qx "COMPILATION_CACHE_LIMIT_SIZE = 24000000000" "$MANAGED_XCCONFIG" || fail 'xcconfig does not bound the store'
  for name in TUIST_XDG_CACHE_HOME TUIST_CACHE_MAX_BYTES XCODE_XCCONFIG_FILE TUIST_COMPILATION_CACHE_CAS_PATH TUIST_CAS_DRAINED_STORE; do
    [ -z "${!name:-}" ] || fail "$name reaches the runner"
  done
  [ ! -e "$RUNNER_CACHES_DIR/module.used" ] && [ ! -e "$RUNNER_CACHES_DIR/xcode.used" ] || fail 'caches read as used before activation'
}

test_activation_attaches_the_volume_once() {
  setup
  stage_runner_caches >/dev/null
  out=$(activate xcode 2>/dev/null) || fail 'xcode activation failed'
  activate xcode >/dev/null 2>&1 || fail 'repeated activation failed'
  eq "$(cat "$RUNNER_CACHES_DIR/xcode.env")" "$out"
  eq "--key tuist-xcode --path $MANAGED_XCODE_CACHE" "$(cat "$work/attached")"
  [ -d "$MANAGED_XCODE_CACHE" ] || fail 'volume not attached at the store path'
  [ -e "$RUNNER_CACHES_DIR/xcode.used" ] || fail 'activation not recorded'
  [ ! -e "$RUNNER_CACHES_DIR/module.used" ] || fail 'xcode activation marked the module cache'
}

test_module_activation_exports_its_environment() {
  setup
  stage_runner_caches >/dev/null
  eq "$(cat "$RUNNER_CACHES_DIR/module.env")" "$(activate module 2>/dev/null)"
  [ -e "$RUNNER_CACHES_DIR/module.used" ] || fail 'module activation not recorded'
  [ ! -e "$RUNNER_CACHES_DIR/xcode.used" ] || fail 'module activation marked the xcode cache'
}

test_activation_exports_nothing_when_the_volume_cannot_attach() {
  setup
  MANAGED_MODULE_CACHE="$work/broken"
  stage_runner_caches >/dev/null
  status=0
  out=$(activate module 2>"$work/err") || status=$?
  eq 3 "$status"
  eq '' "$out"
  grep -q 'empty cache' "$work/err" || fail 'no explanation when the volume cannot attach'
}

test_xcode_activation_includes_the_workflow_xcconfig_last() {
  setup
  stage_runner_caches >/dev/null
  printf 'SWIFT_VERSION = 6\n' >"$work/theirs.xcconfig"
  XCODE_XCCONFIG_FILE="$work/theirs.xcconfig" activate xcode >"$work/env" 2>/dev/null || fail 'xcode activation failed'
  XCODE_XCCONFIG_FILE="$work/theirs.xcconfig" activate xcode >/dev/null 2>&1 || fail 'repeated activation failed'
  eq "#include \"$work/theirs.xcconfig\"" "$(tail -n 1 "$MANAGED_XCCONFIG")"
  eq 1 "$(grep -c '^#include' "$MANAGED_XCCONFIG")"
  grep -qx "XCODE_XCCONFIG_FILE=$MANAGED_XCCONFIG" "$work/env" || fail 'activation does not export the runner xcconfig'
}

test_xcode_activation_resolves_a_relative_workflow_xcconfig() {
  setup
  stage_runner_caches >/dev/null
  mkdir -p "$work/workspace/Config"
  printf 'SWIFT_VERSION = 6\n' >"$work/workspace/Config/CI.xcconfig"
  (cd "$work/workspace" && XCODE_XCCONFIG_FILE=Config/CI.xcconfig activate xcode >/dev/null 2>&1) || fail 'xcode activation failed'
  eq "#include \"$work/workspace/Config/CI.xcconfig\"" "$(tail -n 1 "$MANAGED_XCCONFIG")"
}

test_an_unwritable_xcconfig_leaves_the_compilation_cache_unavailable() {
  setup
  printf 'not a directory' >"$work/blocked"
  MANAGED_XCCONFIG="$work/blocked/managed.xcconfig"
  stage_runner_caches >/dev/null 2>&1
  [ ! -e "$RUNNER_CACHES_DIR/xcode.volume" ] || fail 'a cache without its xcconfig was staged'
  status=0
  out=$(activate xcode 2>"$work/err") || status=$?
  eq 3 "$status"
  eq '' "$out"
  grep -q 'unavailable' "$work/err" || fail 'no explanation for the empty cache'
  [ ! -e "$work/attached" ] || fail 'an unavailable cache attached its volume'
  [ -f "$RUNNER_CACHES_DIR/module.env" ] || fail 'the module cache was not staged'
}

test_staging_failure_leaves_the_runner_without_caches() {
  setup
  printf 'not a directory' >"$work/caches"
  stage_runner_caches >/dev/null
  status=0
  out=$(activate module 2>"$work/err") || status=$?
  eq 0 "$status"
  eq '' "$out"
  grep -q 'does not provide' "$work/err" || fail 'no explanation on a runner without caches'
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

test_compilation_cache_stores_follow_the_store_root() {
  setup
  mkdir -p "$work/volume/data/plugin/v1.1" "$work/volume/data/plugin/tuist-spool"
  ln -s "$work/volume/data" "$MANAGED_XCODE_CACHE"
  CAS_STORE_ROOT="$MANAGED_XCODE_CACHE"
  eq "$MANAGED_XCODE_CACHE/plugin/tuist-spool" "$(cas_spool_dirs)"
  eq "$MANAGED_XCODE_CACHE/plugin" "$(cas_store_dirs)"
  CAS_STORE_ROOT=""
  eq '' "$(cas_spool_dirs)"
  eq '' "$(cas_store_dirs)"
}

for test in $(declare -F | awk '{print $3}' | grep '^test_'); do
  "$test"
  echo "ok: $test"
done
