#!/bin/bash
# Extracts the cache staging functions from dispatch-poll.sh and runs them, and
# tuist-runner-cache, against temporary directories. Never mounts anything.
# shellcheck disable=SC2034
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }

eval "$(awk '/^(stage_runner_caches|stage_managed_cache_volumes|cas_store_root|cas_spool_dirs|cas_store_dirs|managed_xcode_cache_limit)\(\)/ {copy=1} copy {print} copy && /^}$/ {copy=0}' "$ROOT/dispatch-poll.sh")"
for function in stage_runner_caches stage_managed_cache_volumes cas_store_root cas_spool_dirs cas_store_dirs managed_xcode_cache_limit; do
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
  MANAGED_XCODE_CACHE_LIMIT_BYTES=12000000000
  MANAGED_MODULE_CACHE_MAX_BYTES=16000000000
  unset TUIST_XDG_CACHE_HOME TUIST_CACHE_MAX_BYTES XCODE_XCCONFIG_FILE \
    TUIST_COMPILATION_CACHE_CAS_PATH TUIST_CAS_DRAINED_STORE VOLUME_BLOCKS
  # A stand-in for the volume client: records each attach and creates the path,
  # a link into a volume when VOLUME_BLOCKS is set.
  mkdir -p "$work/bin"
  cat >"$work/bin/tuist-cache-volume" <<EOF
#!/bin/bash
echo "\$*" >>"$work/attached"
[ "\$4" = "$work/broken" ] && exit 1
if [ -n "\${VOLUME_BLOCKS:-}" ]; then
  mkdir -p "$work/volume/\$2"
  ln -s "$work/volume/\$2" "\$4"
else
  mkdir -p "\$4"
fi
EOF
  chmod +x "$work/bin/tuist-cache-volume"
  # A stand-in for df: the attached volume holds VOLUME_BLOCKS 1024-byte blocks.
  cat >"$work/bin/df" <<EOF
#!/bin/bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/disk9s1 \$VOLUME_BLOCKS 0 \$VOLUME_BLOCKS 0% $work/volume"
EOF
  chmod +x "$work/bin/df"
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
  grep -qx "COMPILATION_CACHE_LIMIT_SIZE = 12000000000" "$MANAGED_XCCONFIG" || fail 'xcconfig does not bound the store'
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

test_activation_requests_the_size() {
  setup
  stage_runner_caches >/dev/null
  activate module --size 50gb >/dev/null 2>&1 || fail 'sized activation failed'
  eq "--key tuist-module --path $MANAGED_MODULE_CACHE --size 50gb" "$(cat "$work/attached")"
  "$ROOT/tuist-runner-cache" -h 2>&1 | grep -q -- '--size' || fail 'usage does not offer the size'
}

test_invalid_sizes_attach_nothing() {
  setup
  stage_runner_caches >/dev/null
  for size in 0gb 101gb 1.5gb 50 50mb 0050gb; do
    status=0
    activate xcode --size "$size" >/dev/null 2>"$work/err" || status=$?
    eq 2 "$status"
    grep -q 'Invalid cache size' "$work/err" || fail "no explanation for $size"
  done
  status=0
  activate xcode --sized 50gb >/dev/null 2>&1 || status=$?
  eq 2 "$status"
  [ ! -e "$work/attached" ] || fail 'an invalid size attached a volume'
}

test_limits_follow_the_attached_capacity() {
  setup
  stage_runner_caches >/dev/null
  # 50 GB, the capacity a `size: 50gb` volume attaches at.
  export VOLUME_BLOCKS=48828125
  module_env=$(activate module --size 50gb 2>"$work/err") || fail 'module activation failed'
  eq "TUIST_XDG_CACHE_HOME=$MANAGED_MODULE_CACHE"$'\n'"TUIST_CACHE_MAX_BYTES=40000000000" "$module_env"
  grep -q 'holds 50.0 GB; the cache is limited to 40.0 GB' "$work/err" || fail 'no record of the limit'
  activate xcode --size 50gb >/dev/null 2>&1 || fail 'xcode activation failed'
  grep -qx "COMPILATION_CACHE_LIMIT_SIZE = 20000000000" "$MANAGED_XCCONFIG" || fail 'xcconfig limit does not follow the capacity'
  grep -qx "COMPILATION_CACHE_CAS_PATH = $MANAGED_XCODE_CACHE" "$MANAGED_XCCONFIG" || fail 'xcconfig lost the store path'
  eq 20000000000 "$(managed_xcode_cache_limit)"
  unset VOLUME_BLOCKS
}

test_limits_keep_room_on_small_volumes() {
  for case in "29296875 12000000000" "19531250 8000000000" "4882812 1499999744" "976562 249999872"; do
    read -r blocks expected <<<"$case"
    setup
    stage_runner_caches >/dev/null
    VOLUME_BLOCKS="$blocks" activate xcode >/dev/null 2>&1 || fail 'xcode activation failed'
    eq "$expected" "$(managed_xcode_cache_limit)"
  done
}

test_unrestored_volumes_keep_the_default_limits() {
  setup
  stage_runner_caches >/dev/null
  activate module --size 50gb >/dev/null 2>&1 || fail 'module activation failed'
  grep -qx 'TUIST_CACHE_MAX_BYTES=16000000000' "$RUNNER_CACHES_DIR/module.env" || fail 'a local directory changed the module limit'
  eq 12000000000 "$(managed_xcode_cache_limit)"
  rm -f "$MANAGED_XCCONFIG"
  eq 12000000000 "$(managed_xcode_cache_limit)"
}

for test in $(declare -F | awk '{print $3}' | grep '^test_'); do
  "$test"
  echo "ok: $test"
done
