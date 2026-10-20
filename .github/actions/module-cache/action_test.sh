#!/usr/bin/env bash
set -euo pipefail

action=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cache=$(basename "$action" -cache)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
package="$fixture/standalone action"
bash "$action/scripts/package.sh" "$package"
mkdir "$fixture/bin"
export GITHUB_ENV="$fixture/github-env" CAPTURE_ARGS="$fixture/args"

cat > "$fixture/bin/tuist-runner-cache" <<'HELPER'
#!/bin/bash
printf '%s\n' "$@" > "$CAPTURE_ARGS"
printf '%s' "${HELPER_ENV:-}"
exit "${HELPER_EXIT:-0}"
HELPER
chmod +x "$fixture/bin/tuist-runner-cache"

activate() { : > "$GITHUB_ENV"; PATH="$fixture/bin:/usr/bin:/bin" /bin/bash "$package/activate.sh" "$cache"; }
[[ $(ls -A "$package" | LC_ALL=C sort) == $'LICENSE.md\nREADME.md\nSOURCE_COMMIT\naction.yml\nactivate.sh' ]]
[[ $(cat "$package/SOURCE_COMMIT") == "$(git -C "$action" rev-parse HEAD)" ]]
grep -q "activate.sh\" $cache\$" "$package/action.yml"

HELPER_ENV=$'TUIST_XDG_CACHE_HOME=/Users/runner/.tuist-cache-volume\n' activate
printf '%s\n' activate "$cache" > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
[[ $(cat "$GITHUB_ENV") == 'TUIST_XDG_CACHE_HOME=/Users/runner/.tuist-cache-volume' ]]
echo "ok: $cache activation exports the cache environment"

HELPER_EXIT=3 HELPER_ENV='IGNORED=1' activate > "$fixture/out"
[[ ! -s "$GITHUB_ENV" ]]
grep -q '^::warning::' "$fixture/out"
echo 'ok: an unavailable cache warns without failing the job'

HELPER_EXIT=1 activate > "$fixture/out"
[[ ! -s "$GITHUB_ENV" ]]
grep -q '^::warning::' "$fixture/out"
echo 'ok: helper failures never fail the job'

rm "$fixture/bin/tuist-runner-cache"
activate > "$fixture/out"
[[ ! -s "$GITHUB_ENV" ]]
grep -q 'does not provide Tuist runner caches' "$fixture/out"
echo 'ok: other runners are left alone'

printf 'existing files' > "$package/keep"
if bash "$action/scripts/package.sh" "$package" > "$fixture/error" 2>&1; then
  echo 'FAIL: packaging replaced an existing directory' >&2; exit 1
fi
[[ $(cat "$package/keep") == 'existing files' ]]
echo 'ok: packaging never overwrites an existing directory'
