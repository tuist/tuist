#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/server-docker-mix-cache.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/path with spaces"
export GITHUB_OUTPUT="$fixture/output"
cache="$HOME/.cache/tuist-server-docker-mix"

bash "$script" prepare
test -d "$cache/current/_build"
grep -Fx "context=mix-cache=$cache/current" "$GITHUB_OUTPUT"
grep -Fx "export=type=local,dest=$cache/next" "$GITHUB_OUTPUT"

printf 'original\n' > "$cache/current/_build/original"
mkdir -p "$cache/next"
printf 'partial\n' > "$cache/next/partial"
bash "$script" prepare
test -f "$cache/current/_build/original"
test ! -e "$cache/next"

for project in tuist tuist_common tuist_ex noora; do
  mkdir -p "$cache/next/_build/$project"
done
printf 'updated\n' > "$cache/next/_build/updated"
TUIST_MIX_CACHE_EXPORTED=true bash "$script" commit
test -f "$cache/current/_build/updated"
test ! -e "$cache/current/_build/original"
test ! -e "$cache/next"

# Neither a failed export nor an incomplete successful export replaces current.
for exported in false true; do
  mkdir -p "$cache/next/_build/tuist"
  if [[ "$exported" == false ]]; then
    for project in tuist_common tuist_ex noora; do
      mkdir -p "$cache/next/_build/$project"
    done
  fi
  TUIST_MIX_CACHE_EXPORTED="$exported" bash "$script" commit
  test -f "$cache/current/_build/updated"
  test ! -e "$cache/next"
done

if bash "$script" invalid; then
  echo 'Unknown operation unexpectedly succeeded' >&2
  exit 1
fi
echo 'Production Mix cache lifecycle tests passed.'
