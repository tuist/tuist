#!/usr/bin/env bash
set -euo pipefail

mise exec -- bazel build //:kura_lib_test >/dev/null

measurements=()
for _ in 1 2 3 4 5; do
  output="$(bazel-bin/kura_lib_test \
    --exact store::tests::concurrent_recipe_replication_and_high_fanout_eviction_stay_consistent \
    --nocapture 2>&1)"
  measurement="$(printf '%s\n' "$output" | awk -F= '/CHUNKING_STRESS_NS=/{print $2}')"
  if [[ ! "$measurement" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$output" >&2
    exit 1
  fi
  measurements+=("$measurement")
done

median="$(printf '%s\n' "${measurements[@]}" | sort -n | sed -n '3p')"
printf 'METRIC concurrent_recipe_cascade_ns=%s\n' "$median"
