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

# The volume's fill, in percent, while Gradle's local build cache exists and after it is gone.
cat > "$fixture/bin/df" <<'DF'
#!/bin/bash
if [ -e "${!#}/build-cache-1" ]; then used=${USED_WITH_BUILD_CACHE:-10}; else used=${USED_WITHOUT_BUILD_CACHE:-10}; fi
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nvolume 1000 %s %s %s%% /volume\n' "$used" "$((100 - used))" "$used"
DF
chmod +x "$fixture/bin/df"

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

fill() { rm -rf "$fixture/home/.gradle"; mkdir -p "$fixture/home/.gradle/caches/"{build-cache-1,modules-2} "$fixture/home/.gradle/wrapper/dists"; }

fill
USED_WITH_BUILD_CACHE=74 USED_WITHOUT_BUILD_CACHE=10 setup > "$fixture/out"
[[ -d "$fixture/home/.gradle/caches/build-cache-1" && -d "$fixture/home/.gradle/caches/modules-2" ]]
echo 'ok: a cache below three quarters full is left alone'

fill
USED_WITH_BUILD_CACHE=75 USED_WITHOUT_BUILD_CACHE=74 setup > "$fixture/out"
[[ ! -e "$fixture/home/.gradle/caches/build-cache-1" && -d "$fixture/home/.gradle/caches/modules-2" ]]
if grep -q '::warning::' "$fixture/out"; then echo 'FAIL: unexpected warning' >&2; exit 1; fi
echo 'ok: a nearly full cache drops only the local build cache when that is enough'

fill
USED_WITH_BUILD_CACHE=90 USED_WITHOUT_BUILD_CACHE=75 setup > "$fixture/out"
[[ -z $(ls -A "$fixture/home/.gradle/caches") && -d "$fixture/home/.gradle/wrapper/dists" ]]
grep -q '^::warning::The Gradle cache was nearly full' "$fixture/out"
[[ -f "$fixture/home/.gradle/init.d/tuist-gradle-cache.gradle" ]]
echo 'ok: a cache still nearly full without the build cache starts empty and keeps the wrapper'

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
