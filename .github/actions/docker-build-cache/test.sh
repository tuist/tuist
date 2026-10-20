#!/usr/bin/env bash
set -euo pipefail

action_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT
export RUNNER_TEMP="$fixtures/runner temp"
export GITHUB_OUTPUT="$fixtures/outputs"
export TUIST_DOCKER_REGISTRY_CACHE='ghcr.io/tuist/tuist-buildcache:server'
export TUIST_DOCKER_CACHE_DIRECTORY="$RUNNER_TEMP/docker-build-cache"
cache_root="$TUIST_DOCKER_CACHE_DIRECTORY"

prepare() {
  : > "$GITHUB_OUTPUT"
  bash "$action_dir/prepare.sh"
}

mkdir -p "$cache_root/next/blobs"
printf 'incomplete export' > "$cache_root/next/blobs/stale"
prepare
grep -Fqx "directory=$cache_root" "$GITHUB_OUTPUT"
grep -Fqx "cache-from=type=registry,ref=$TUIST_DOCKER_REGISTRY_CACHE" "$GITHUB_OUTPUT"
grep -Fqx "type=local,dest=$cache_root/next,mode=max,ignore-error=true" "$GITHUB_OUTPUT"
grep -Fqx "type=registry,ref=$TUIST_DOCKER_REGISTRY_CACHE,mode=max" "$GITHUB_OUTPUT"
test ! -e "$cache_root/next"

mkdir -p "$cache_root/current/blobs"
printf '{"schemaVersion":2,"manifests":[]}' > "$cache_root/current/index.json"
printf 'old layer' > "$cache_root/current/blobs/old"
prepare
grep -Fqx "cache-from=type=local,src=$cache_root/current" "$GITHUB_OUTPUT"
if grep -Fq 'cache-from=type=registry' "$GITHUB_OUTPUT"; then
  echo 'Warm import unexpectedly reads the registry cache.' >&2
  exit 1
fi
grep -Fqx "type=registry,ref=$TUIST_DOCKER_REGISTRY_CACHE,mode=max" "$GITHUB_OUTPUT"

# A missing/failed optional local export preserves the existing cache.
mkdir -p "$cache_root/next/blobs"
printf 'partial export' > "$cache_root/next/blobs/partial"
bash "$action_dir/commit.sh" > "$fixtures/optional-export.log"
grep -Fq 'retaining the previous snapshot' "$fixtures/optional-export.log"
test -f "$cache_root/current/blobs/old"
test ! -e "$cache_root/next"

mkdir -p "$cache_root/next/blobs"
printf '{"schemaVersion":2,"manifests":[]}' > "$cache_root/next/index.json"
printf 'new layer' > "$cache_root/next/blobs/new"
bash "$action_dir/commit.sh"
test -d "$cache_root"
test -s "$cache_root/current/index.json"
test -f "$cache_root/current/blobs/new"
test ! -e "$cache_root/current/blobs/old"
test ! -e "$cache_root/next"

# Empty indexes are not usable cache sources.
: > "$cache_root/current/index.json"
prepare
grep -Fqx "cache-from=type=registry,ref=$TUIST_DOCKER_REGISTRY_CACHE" "$GITHUB_OUTPUT"

for invalid in $'registry\ninjected=value' $'registry\rinjected=value' 'registry,mode=min'; do
  if TUIST_DOCKER_REGISTRY_CACHE="$invalid" prepare > "$fixtures/invalid.log" 2>&1; then
    echo 'Accepted an invalid registry cache reference.' >&2
    exit 1
  fi
  grep -Fq 'must not contain commas or newlines' "$fixtures/invalid.log"
done

mkdir -p "$fixtures/outside"
ln -s "$fixtures/outside" "$cache_root/next"
if prepare > "$fixtures/symlink.log" 2>&1; then
  echo 'Accepted a symlink cache directory during preparation.' >&2
  exit 1
fi
grep -Fq 'must not be symlinks' "$fixtures/symlink.log"
if bash "$action_dir/commit.sh" > "$fixtures/symlink.log" 2>&1; then
  echo 'Accepted a symlink cache directory during rotation.' >&2
  exit 1
fi
grep -Fq 'must not be symlinks' "$fixtures/symlink.log"
test -d "$fixtures/outside"

echo 'Docker build cache script tests passed.'
