#!/usr/bin/env bash
set -euo pipefail

action=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
package="$fixture/standalone action"
bash "$action/scripts/package.sh" "$package"
mkdir "$fixture/bin" "$fixture/home" "$fixture/workspace"
export CAPTURE_ARGS="$fixture/args" HOME="$fixture/home"

cat > "$fixture/bin/tuist-cache-volume" <<'CLIENT'
#!/bin/bash
if [ "$1" = -h ]; then
  echo '  -key string' >&2
  if [ -n "${CLIENT_SUPPORTS_SIZE-1}" ]; then
    echo '  -size string' >&2
    exit 0
  fi
  exit 2
fi
printf '%s\n' "$@" > "$CAPTURE_ARGS"
exit "${CLIENT_EXIT:-0}"
CLIENT
chmod +x "$fixture/bin/tuist-cache-volume"

setup() { (cd "$fixture/workspace" && PATH="$fixture/bin:/usr/bin:/bin" /bin/bash "$package/setup.sh"); }
[[ $(ls -A "$package" | LC_ALL=C sort) == $'LICENSE.md\nREADME.md\nSOURCE_COMMIT\naction.yml\nsetup.sh' ]]
[[ $(cat "$package/SOURCE_COMMIT") == "$(git -C "$action" rev-parse HEAD)" ]]

unset GRADLE_USER_HOME
setup
printf '%s\n' --key tuist-gradle --path "$fixture/home/.gradle/caches" --path "$fixture/home/.gradle/wrapper" > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
grep -q 'Cleanup' "$fixture/home/.gradle/init.d/tuist-gradle-cache.gradle"
grep -q 'setRemoveUnusedEntriesAfterDays(7)' "$fixture/home/.gradle/init.d/tuist-gradle-cache.gradle"
echo 'ok: the default Gradle user home is cached and cleaned up'

GRADLE_USER_HOME=.gradle setup
printf '%s\n' --key tuist-gradle --path "$fixture/workspace/.gradle/caches" --path "$fixture/workspace/.gradle/wrapper" > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
[[ -f "$fixture/workspace/.gradle/init.d/tuist-gradle-cache.gradle" ]]
echo 'ok: a relative GRADLE_USER_HOME resolves against the working directory'

TUIST_GRADLE_CACHE_SIZE=50gb setup > "$fixture/out"
printf '%s\n' --key tuist-gradle --path "$fixture/home/.gradle/caches" --path "$fixture/home/.gradle/wrapper" --size 50gb > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
if grep -q '::warning::' "$fixture/out"; then echo 'FAIL: unexpected warning' >&2; exit 1; fi
echo 'ok: the size is passed to a client that supports it'

CLIENT_SUPPORTS_SIZE= TUIST_GRADLE_CACHE_SIZE=50gb setup > "$fixture/out"
printf '%s\n' --key tuist-gradle --path "$fixture/home/.gradle/caches" --path "$fixture/home/.gradle/wrapper" > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
grep -q '^::warning::This runner image does not support the size input' "$fixture/out"
echo 'ok: an older client attaches without the size and warns'

rm -rf "$fixture/home/.gradle"
CLIENT_EXIT=2 TUIST_GRADLE_CACHE_SIZE=50 setup > "$fixture/out"
grep -q '^::warning::Could not attach the Gradle cache' "$fixture/out"
[[ ! -e "$fixture/home/.gradle/init.d" ]]
echo 'ok: a size the client rejects warns without failing the job'

rm -rf "$fixture/home/.gradle"
CLIENT_EXIT=2 setup > "$fixture/out"
grep -q '^::warning::' "$fixture/out"
[[ ! -e "$fixture/home/.gradle/init.d" ]]
echo 'ok: client failures warn without failing the job'

rm "$fixture/bin/tuist-cache-volume"
if [[ ! -x /__e/tuist-cache-volume ]]; then
  setup > "$fixture/out"
  grep -q 'does not provide Tuist cache volumes' "$fixture/out"
  [[ ! -e "$fixture/home/.gradle/init.d" ]]
  echo 'ok: other runners are left alone'
else
  echo 'skip: container client is installed'
fi

printf 'existing files' > "$package/keep"
if bash "$action/scripts/package.sh" "$package" > "$fixture/error" 2>&1; then
  echo 'FAIL: packaging replaced an existing directory' >&2; exit 1
fi
[[ $(cat "$package/keep") == 'existing files' ]]
echo 'ok: packaging never overwrites an existing directory'
