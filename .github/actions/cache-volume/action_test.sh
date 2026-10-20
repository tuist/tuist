#!/usr/bin/env bash
set -euo pipefail

action=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
package="$fixture/standalone action"
bash "$action/scripts/package.sh" "$package"
mkdir "$fixture/bin"
export GITHUB_OUTPUT="$fixture/github-output" CAPTURE_ARGS="$fixture/args"
export TUIST_VOLUME_KEY=gradle-caches TUIST_VOLUME_PATH='~/.gradle/caches'
cd "$fixture"

cat > "$fixture/bin/tuist-cache-volume" <<'CLIENT'
#!/bin/bash
if [ "$1" = -h ]; then
  echo 'Usage of tuist-cache-volume:' >&2
  echo '  -key string' >&2
  echo '  -path value' >&2
  if [ -n "${CLIENT_SUPPORTS_SIZE-1}" ]; then
    echo '  -size string' >&2
    exit 0
  fi
  exit 2
fi
printf '%s\n' "$@" > "$CAPTURE_ARGS"
printf 'cache-hit=%s\n' "${CLIENT_HIT:-true}" >> "$GITHUB_OUTPUT"
exit "${CLIENT_EXIT:-0}"
CLIENT
chmod +x "$fixture/bin/tuist-cache-volume"

attach() { PATH="$fixture/bin" /bin/bash "$package/attach.sh"; }
[[ $(ls -A "$package" | LC_ALL=C sort) == $'LICENSE.md\nREADME.md\nSOURCE_COMMIT\naction.yml\nattach.sh' ]]
[[ $(cat "$package/SOURCE_COMMIT") == "$(git -C "$action" rev-parse HEAD)" ]]
attach
[[ $(cat "$GITHUB_OUTPUT") == cache-hit=true ]]
echo 'ok: standalone package forwards cache hits'

: > "$GITHUB_OUTPUT"
CLIENT_HIT=false attach
[[ $(cat "$GITHUB_OUTPUT") == cache-hit=false ]]
echo 'ok: cache misses are forwarded'

export TUIST_VOLUME_PATH='cache directory/$(touch injected);*'
attach
printf '%s\n' --key gradle-caches --path "$TUIST_VOLUME_PATH" > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
[[ ! -e injected ]]
echo 'ok: inputs remain literal arguments'

export TUIST_VOLUME_PATH=$'  .npm\n\n\t~/.gradle/caches  \r\n   \n cache dir/$(touch injected);* \n'
attach
printf '%s\n' --key gradle-caches --path .npm --path '~/.gradle/caches' --path 'cache dir/$(touch injected);*' > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
[[ ! -e injected ]]
echo 'ok: each nonblank line becomes one trimmed path argument'

export TUIST_VOLUME_PATH=$' \n\t\n'
rm "$CAPTURE_ARGS"
status=0
attach > "$fixture/error" 2>&1 || status=$?
[[ "$status" != 0 && ! -e "$CAPTURE_ARGS" ]]
grep -q 'at least one path' "$fixture/error"
echo 'ok: blank paths fail before calling the client'
export TUIST_VOLUME_PATH=cache

export TUIST_VOLUME_PATH=$'~/.npm\n'
attach
printf '%s\n' --key gradle-caches --path '~/.npm' > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
echo 'ok: a block path with a single line is one path'
export TUIST_VOLUME_PATH=cache

for key in '' ' ' $'\t\n'; do
  TUIST_VOLUME_KEY="$key" attach
  printf '%s\n' --key tuist-default --path cache > "$fixture/expected"
  cmp "$fixture/expected" "$CAPTURE_ARGS"
done
echo 'ok: an omitted key attaches the default volume'

for key in tuist-default tuist-gradle Tuist-Cache TUIST-X; do
  rm -f "$CAPTURE_ARGS"
  status=0
  TUIST_VOLUME_KEY="$key" attach > "$fixture/error" 2>&1 || status=$?
  [[ "$status" != 0 && ! -e "$CAPTURE_ARGS" ]]
  grep -q 'reserved for Tuist' "$fixture/error"
done
TUIST_VOLUME_KEY=my-tuist-cache attach
echo 'ok: keys starting with tuist- are reserved'

TUIST_VOLUME_SIZE=' 50gb ' attach > "$fixture/log" 2>&1
printf '%s\n' --key gradle-caches --path cache --size 50gb > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
if grep -q '::warning::' "$fixture/log"; then echo 'FAIL: unexpected warning' >&2; exit 1; fi
TUIST_VOLUME_SIZE='50' attach
printf '%s\n' --key gradle-caches --path cache --size 50 > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
echo 'ok: size is passed to a client that supports it, which validates it'

CLIENT_SUPPORTS_SIZE= TUIST_VOLUME_SIZE=50gb attach > "$fixture/log" 2>&1
printf '%s\n' --key gradle-caches --path cache > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
grep -q '::warning::This runner image does not support the size input' "$fixture/log"
echo 'ok: an older client attaches without the size and warns'

TUIST_VOLUME_SIZE= attach > "$fixture/log" 2>&1
printf '%s\n' --key gradle-caches --path cache > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
if grep -q '::warning::' "$fixture/log"; then echo 'FAIL: unexpected warning' >&2; exit 1; fi
echo 'ok: no size attaches without one'
status=0
CLIENT_EXIT=42 attach || status=$?
[[ "$status" == 42 ]]
echo 'ok: client failures propagate'

rm "$fixture/bin/tuist-cache-volume"
if [[ ! -x /__e/tuist-cache-volume ]]; then
  status=0
  attach > "$fixture/error" 2>&1 || status=$?
  [[ "$status" != 0 ]]
  grep -q 'requires a Tuist Linux or macOS runner' "$fixture/error"
  echo 'ok: missing client explains the runner requirement'
else
  echo 'skip: container client is installed'
fi

printf 'existing files' > "$package/keep"
if bash "$action/scripts/package.sh" "$package" > "$fixture/error" 2>&1; then
  echo 'FAIL: packaging replaced an existing directory' >&2; exit 1
fi
[[ $(cat "$package/keep") == 'existing files' ]]
echo 'ok: packaging never overwrites an existing directory'
