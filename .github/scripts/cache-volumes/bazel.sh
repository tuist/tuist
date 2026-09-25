#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$RUNNER_TEMP/bazel-cache/repository" "$RUNNER_TEMP/bazel-cache/disk"
{
  echo "common --repository_cache=$RUNNER_TEMP/bazel-cache/repository"
  echo "build --disk_cache=$RUNNER_TEMP/bazel-cache/disk"
  echo "build --experimental_disk_cache_gc_max_size=12G"
  echo "build --experimental_disk_cache_gc_max_age=7d"
  echo "build --experimental_disk_cache_gc_idle_delay=0s"
} >> "$HOME/.bazelrc"
