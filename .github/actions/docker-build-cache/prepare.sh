#!/usr/bin/env bash
set -euo pipefail

cache_root="${RUNNER_TEMP:?}/docker-build-cache"
registry_cache="${TUIST_DOCKER_REGISTRY_CACHE:?}"

# BuildKit cache options are CSV and GitHub outputs are line-delimited.
for value in "$cache_root" "$registry_cache"; do
  case "$value" in
    *$'\n'*|*$'\r'*|*,*)
      echo '::error::Docker cache paths and registry references must not contain commas or newlines.' >&2
      exit 1
      ;;
  esac
done

for path in "$cache_root" "$cache_root/current" "$cache_root/next"; do
  if [ -L "$path" ]; then
    echo '::error::Docker cache directories must not be symlinks.' >&2
    exit 1
  fi
done

mkdir -p "$cache_root"
rm -rf -- "$cache_root/next"

if [ -s "$cache_root/current/index.json" ]; then
  cache_from="type=local,src=$cache_root/current"
  echo 'Using the volume-backed BuildKit layer cache.'
else
  cache_from="type=registry,ref=$registry_cache"
  echo 'No local BuildKit snapshot; using the registry cache.'
fi

{
  printf 'directory=%s\n' "$cache_root"
  printf 'cache-from=%s\n' "$cache_from"
  echo 'cache-to<<EOF'
  printf 'type=local,dest=%s/next,mode=max,ignore-error=true\n' "$cache_root"
  printf 'type=registry,ref=%s,mode=max\n' "$registry_cache"
  echo 'EOF'
} >> "${GITHUB_OUTPUT:?}"
