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
printf '%s\n' "$@" > "$CAPTURE_ARGS"
exit "${CLIENT_EXIT:-0}"
CLIENT
chmod +x "$fixture/bin/tuist-cache-volume"

setup() { (cd "$fixture/workspace" && PATH="$fixture/bin:/usr/bin:/bin" /bin/bash "$package/setup.sh"); }
[[ $(ls -A "$package" | LC_ALL=C sort) == $'LICENSE.md\nREADME.md\nSOURCE_COMMIT\naction.yml\nsetup.sh' ]]
[[ $(cat "$package/SOURCE_COMMIT") == "$(git -C "$action" rev-parse HEAD)" ]]

unset GRADLE_USER_HOME
setup
printf '%s\n' --key gradle --path "$fixture/home/.gradle/caches" --path "$fixture/home/.gradle/wrapper" > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
grep -q 'Cleanup' "$fixture/home/.gradle/init.d/tuist-gradle-cache.gradle"
grep -q 'setRemoveUnusedEntriesAfterDays(7)' "$fixture/home/.gradle/init.d/tuist-gradle-cache.gradle"
echo 'ok: the default Gradle user home is cached and cleaned up'

GRADLE_USER_HOME=.gradle setup
printf '%s\n' --key gradle --path "$fixture/workspace/.gradle/caches" --path "$fixture/workspace/.gradle/wrapper" > "$fixture/expected"
cmp "$fixture/expected" "$CAPTURE_ARGS"
[[ -f "$fixture/workspace/.gradle/init.d/tuist-gradle-cache.gradle" ]]
echo 'ok: a relative GRADLE_USER_HOME resolves against the working directory'

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
