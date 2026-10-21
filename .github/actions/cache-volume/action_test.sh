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
