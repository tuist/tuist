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
diff <(sed 's/xcode/module/' "$source_dir/xcode-cache/buildkite/hooks/pre-command") "$source_dir/module-cache/buildkite/hooks/pre-command"
diff <(sed 's/xcode/module/' "$source_dir/xcode-cache/gitlab/xcode-cache.yml") "$source_dir/module-cache/gitlab/module-cache.yml"
echo 'ok: the two caches differ only by name'
