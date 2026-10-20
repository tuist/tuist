#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/server-docker-mix-cache.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export RUNNER_TEMP="$fixture/path with spaces"
export GITHUB_OUTPUT="$fixture/output"
cache="$RUNNER_TEMP/server-docker-mix-cache"

bash "$script" prepare
test -d "$cache/current/deps"
test -d "$cache/current/_build"
grep -Fx "context=mix-cache=$cache/current" "$GITHUB_OUTPUT"
grep -Fx "export=type=local,dest=$cache/next" "$GITHUB_OUTPUT"

printf 'original\n' > "$cache/current/_build/original"
mkdir -p "$cache/next"
printf 'partial\n' > "$cache/next/partial"
bash "$script" prepare
test -f "$cache/current/_build/original"
test ! -e "$cache/next"

mkdir -p "$cache/next/deps" "$cache/next/_build"
printf 'updated\n' > "$cache/next/_build/updated"
TUIST_MIX_CACHE_EXPORTED=true bash "$script" commit
test -f "$cache/current/_build/updated"
test ! -e "$cache/current/_build/original"
test ! -e "$cache/next"

# Neither a failed export nor an incomplete successful export replaces current.
for exported in false true; do
  mkdir -p "$cache/next/deps"
  TUIST_MIX_CACHE_EXPORTED="$exported" bash "$script" commit
  test -f "$cache/current/_build/updated"
  test ! -e "$cache/next"
done

if bash "$script" invalid; then
  echo 'Unknown operation unexpectedly succeeded' >&2
  exit 1
fi
echo 'Production Mix cache lifecycle tests passed.'
