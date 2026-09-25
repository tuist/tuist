#!/usr/bin/env bash
set -euo pipefail

: "${MIX_CACHE_IDENTITY:?Missing Mix cache identity}"
: "${RUNNER_TEMP:?Missing runner temporary directory}"
: "${GITHUB_ENV:?Missing GitHub environment file}"
: "${GITHUB_OUTPUT:?Missing GitHub output file}"

for directory in deps _build; do
  if [ -e "$directory" ] || [ -L "$directory" ]; then
    if [ -L "$directory" ] || [ ! -d "$directory" ] || [ -n "$(ls -A "$directory")" ]; then
      echo "::error::Attach Mix volumes before populating $directory."
      exit 1
    fi
  fi
done

mkdir -p "$RUNNER_TEMP/mix-cache"
cache_root=$(readlink -f "$RUNNER_TEMP/mix-cache")
cache_hit=${MIX_VOLUME_HIT:-false}
if [ ! -f "$cache_root/.mix-cache-identity" ] || [ "$(cat "$cache_root/.mix-cache-identity")" != "$MIX_CACHE_IDENTITY" ]; then
  # Only discard build state in this job's private clone, never the mount root.
  rm -rf "$cache_root/deps" "$cache_root/_build"
  cache_hit=false
  echo 'Preparing an empty Mix cache for this toolchain and lockfile.'
fi

for directory in deps _build; do
  mkdir -p "$cache_root/$directory"
  if [ -d "$directory" ]; then rmdir "$directory"; fi
  ln -s "$cache_root/$directory" "$directory"
done
printf '%s\n' "$MIX_CACHE_IDENTITY" > "$cache_root/.mix-cache-identity"
echo "MIX_DEPS_PATH=$cache_root/deps" >> "$GITHUB_ENV"
echo "MIX_BUILD_ROOT=$cache_root/_build" >> "$GITHUB_ENV"
echo "cache-hit=$cache_hit" >> "$GITHUB_OUTPUT"
