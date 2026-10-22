#!/usr/bin/env bash
# The entry points run inside single-quoted `bash -c` / `sh -c` scripts on purpose.
# shellcheck disable=SC2016
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
export CAPTURE_ARGS="$fixture/args"
cat > "$fixture/bin/tuist-runner-cache" <<'HELPER'
#!/bin/bash
if [ "$1" = -h ]; then
  if [ -n "${HELPER_SUPPORTS_SIZE-1}" ]; then
    echo 'usage: tuist-runner-cache activate <module|xcode> [--size NGB]' >&2
    exit 0
  fi
  echo 'usage: tuist-runner-cache activate <module|xcode>' >&2
  exit 2
fi
printf '%s\n' "$@" > "$CAPTURE_ARGS"
printf '%s' "${HELPER_ENV:-}"
exit "${HELPER_EXIT:-0}"
HELPER
chmod +x "$fixture/bin/tuist-runner-cache"
export HELPER_ENV=$'TUIST_TEST_CACHE=/Users/runner/My Cache\nnot an assignment\nTUIST_TEST_LIMIT=1000\n'

# Sources an entry point the way its provider does, then runs a later command
# in the same shell. The later command must run and see the exports.
run_buildkite() { PATH="$fixture/bin:/usr/bin:/bin" bash -c '. "$1"; printf "after %s|%s\n" "${TUIST_TEST_CACHE:-}" "${TUIST_TEST_LIMIT:-}"' _ "$1"; }
run_gitlab() { PATH="$fixture/bin:/usr/bin:/bin" "$2" -c '. "$1"; printf "after %s|%s\n" "${TUIST_TEST_CACHE:-}" "${TUIST_TEST_LIMIT:-}"' _ "$1"; }

for cache in xcode module; do
  hook="$source_dir/$cache-cache/buildkite/hooks/pre-command"
  sed -n 's/^      //p' "$source_dir/$cache-cache/gitlab/$cache-cache.yml" > "$fixture/$cache-gitlab.sh"
  [[ -s "$fixture/$cache-gitlab.sh" ]]
  grep -q "^\.tuist-$cache-cache:" "$source_dir/$cache-cache/gitlab/$cache-cache.yml"

  [[ $(run_buildkite "$hook") == 'after /Users/runner/My Cache|1000' ]]
  [[ $(cat "$CAPTURE_ARGS") == $'activate\n'"$cache" ]]
  for shell in bash sh; do
    [[ $(run_gitlab "$fixture/$cache-gitlab.sh" "$shell") == 'after /Users/runner/My Cache|1000' ]]
    [[ $(cat "$CAPTURE_ARGS") == $'activate\n'"$cache" ]]
  done
  echo "ok: $cache cache exports the runner environment to later commands"

  upper=$(printf '%s' "$cache" | tr '[:lower:]' '[:upper:]')
  for entry in "buildkite $hook BUILDKITE_PLUGIN_${upper}_CACHE_SIZE" "bash $fixture/$cache-gitlab.sh TUIST_${upper}_CACHE_SIZE" "sh $fixture/$cache-gitlab.sh TUIST_${upper}_CACHE_SIZE"; do
    read -r shell script size_variable <<< "$entry"
    run() { if [ "$shell" = buildkite ]; then run_buildkite "$script"; else run_gitlab "$script" "$shell"; fi; }
    [[ $(export "$size_variable=50gb"; run 2> "$fixture/err") == 'after /Users/runner/My Cache|1000' ]]
    [[ $(cat "$CAPTURE_ARGS") == $'activate\n'"$cache"$'\n--size\n50gb' ]]
    [[ ! -s "$fixture/err" ]]
    [[ $(export "$size_variable=50gb" HELPER_SUPPORTS_SIZE=; run 2> "$fixture/err") == 'after /Users/runner/My Cache|1000' ]]
    [[ $(cat "$CAPTURE_ARGS") == $'activate\n'"$cache" ]]
    grep -q '^Warning: this runner image does not support' "$fixture/err"
  done
  echo "ok: $cache cache passes the size only to a helper that supports it"

  for code in 3 1; do
    [[ $(HELPER_EXIT=$code run_buildkite "$hook" 2> "$fixture/err") == 'after |' ]]
    grep -q '^Warning:' "$fixture/err"
    [[ $(HELPER_EXIT=$code run_gitlab "$fixture/$cache-gitlab.sh" sh 2> "$fixture/err") == 'after |' ]]
    grep -q '^Warning:' "$fixture/err"
  done
  echo "ok: $cache cache warns and continues when the cache is unavailable"

  mv "$fixture/bin/tuist-runner-cache" "$fixture/helper"
  [[ $(run_buildkite "$hook") == *'does not provide Tuist runner caches'*'after |' ]]
  [[ $(run_gitlab "$fixture/$cache-gitlab.sh" sh) == *'does not provide Tuist runner caches'*'after |' ]]
  mv "$fixture/helper" "$fixture/bin/tuist-runner-cache"
  echo "ok: $cache cache leaves other runners alone"

  bash "$source_dir/$cache-cache/buildkite/package.sh" "$fixture/$cache-buildkite"
  [[ -x "$fixture/$cache-buildkite/hooks/pre-command" ]]
  [[ $(cd "$fixture/$cache-buildkite" && find . -type f | LC_ALL=C sort) == $'./LICENSE.md\n./README.md\n./SOURCE_COMMIT\n./hooks/pre-command\n./plugin.yml' ]]
  [[ $(run_buildkite "$fixture/$cache-buildkite/hooks/pre-command") == 'after /Users/runner/My Cache|1000' ]]
  bash "$source_dir/$cache-cache/gitlab/package.sh" "$fixture/$cache-gitlab"
  [[ $(cd "$fixture/$cache-gitlab" && find . -type f | LC_ALL=C sort) == $'./LICENSE.md\n./README.md\n./SOURCE_COMMIT\n./'"$cache-cache.yml" ]]
  [[ $(cat "$fixture/$cache-gitlab/SOURCE_COMMIT") == "$(git -C "$source_dir" rev-parse HEAD)" ]]
  echo "ok: $cache cache packages are self-contained"
done

cmp "$source_dir/xcode-cache/buildkite/package.sh" "$source_dir/module-cache/buildkite/package.sh"
cmp "$source_dir/xcode-cache/gitlab/package.sh" "$source_dir/module-cache/gitlab/package.sh"
diff <(sed 1,2d "$source_dir/xcode-cache/buildkite/plugin.yml") <(sed 1,2d "$source_dir/module-cache/buildkite/plugin.yml")
diff <(sed 's/xcode/module/; s/XCODE/MODULE/' "$source_dir/xcode-cache/buildkite/hooks/pre-command") "$source_dir/module-cache/buildkite/hooks/pre-command"
diff <(sed 's/xcode/module/; s/XCODE/MODULE/' "$source_dir/xcode-cache/gitlab/xcode-cache.yml") "$source_dir/module-cache/gitlab/module-cache.yml"
echo 'ok: the two caches differ only by name'

# Gradle: every entry point attaches the same volume and writes the same init
# script as the GitHub action.
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
sed -n "/<<'GROOVY'$/,/^GROOVY$/p" "$source_dir/../../.github/actions/gradle-cache/setup.sh" | sed '1d;$d' > "$fixture/expected-init"
[[ -s "$fixture/expected-init" ]]
sed -n 's/^      //p' "$source_dir/gradle-cache/gitlab/gradle-cache.yml" > "$fixture/gradle-gitlab.sh"
gradle_hook="$source_dir/gradle-cache/buildkite/hooks/pre-command"

run_gradle() {
  rm -rf "$fixture/gradle-home"
  (cd "$fixture" && HOME="$fixture/gradle-home" PATH="$fixture/bin:/usr/bin:/bin" "$1" -c '. "$1"; echo after' _ "$2")
}
for entry in "bash $gradle_hook BUILDKITE_PLUGIN_GRADLE_CACHE_SIZE" "bash $fixture/gradle-gitlab.sh TUIST_GRADLE_CACHE_SIZE" "sh $fixture/gradle-gitlab.sh TUIST_GRADLE_CACHE_SIZE"; do
  read -r shell script size_variable <<< "$entry"
  [[ $(run_gradle "$shell" "$script") == *after ]]
  printf '%s\n' --key tuist-gradle --path "$fixture/gradle-home/.gradle/caches" --path "$fixture/gradle-home/.gradle/wrapper" > "$fixture/expected-args"
  cmp "$fixture/expected-args" "$CAPTURE_ARGS"
  cmp "$fixture/expected-init" "$fixture/gradle-home/.gradle/init.d/tuist-gradle-cache.gradle"

  [[ $(CLIENT_EXIT=2 run_gradle "$shell" "$script" 2> "$fixture/err") == *after ]]
  grep -q '^Warning:' "$fixture/err"
  [[ ! -e "$fixture/gradle-home/.gradle/init.d" ]]

  [[ $(export "$size_variable=50gb"; run_gradle "$shell" "$script" 2> "$fixture/err") == *after ]]
  printf '%s\n' --size 50gb >> "$fixture/expected-args"
  cmp "$fixture/expected-args" "$CAPTURE_ARGS"
  [[ ! -s "$fixture/err" ]]

  [[ $(export "$size_variable=50gb" CLIENT_SUPPORTS_SIZE=; run_gradle "$shell" "$script" 2> "$fixture/err") == *after ]]
  sed '$d' "$fixture/expected-args" | sed '$d' > "$fixture/expected-args-without-size"
  cmp "$fixture/expected-args-without-size" "$CAPTURE_ARGS"
  grep -q '^Warning: this runner image does not support' "$fixture/err"
  [[ -f "$fixture/gradle-home/.gradle/init.d/tuist-gradle-cache.gradle" ]]
done
echo 'ok: Gradle entry points attach the cache and install the cleanup init script'
echo 'ok: Gradle entry points pass the size only to a client that supports it'

bash "$source_dir/gradle-cache/buildkite/package.sh" "$fixture/gradle-buildkite"
[[ -x "$fixture/gradle-buildkite/hooks/pre-command" ]]
bash "$source_dir/gradle-cache/gitlab/package.sh" "$fixture/gradle-gitlab"
[[ -f "$fixture/gradle-gitlab/gradle-cache.yml" ]]
echo 'ok: Gradle packages are self-contained'
