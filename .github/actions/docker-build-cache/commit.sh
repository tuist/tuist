#!/usr/bin/env bash
set -euo pipefail

cache_root="${TUIST_DOCKER_CACHE_DIRECTORY:?}"
for path in "$cache_root" "$cache_root/current" "$cache_root/next"; do
  if [ -L "$path" ]; then
    echo '::error::Docker cache directories must not be symlinks.' >&2
    exit 1
  fi
done

if [ ! -s "$cache_root/next/index.json" ]; then
  echo '::warning::No local BuildKit cache was exported; retaining the previous snapshot.'
  rm -rf -- "$cache_root/next"
  exit 0
fi

# Exporting to a fresh directory drops blobs no longer referenced by this build.
# Keep the mounted root in place; only rotate its children.
rm -rf -- "$cache_root/current"
mv -- "$cache_root/next" "$cache_root/current"
