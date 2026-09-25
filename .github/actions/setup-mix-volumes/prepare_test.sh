#!/usr/bin/env bash
set -euo pipefail

action_dir=$(cd "$(dirname "$0")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export RUNNER_TEMP="$fixture/runner"
export GITHUB_ENV="$fixture/env"
export GITHUB_OUTPUT="$fixture/output"
export MIX_CACHE_IDENTITY='v1-elixir-otp-lock-a'
export MIX_VOLUME_HIT=false
mkdir -p "$fixture/project"
cd "$fixture/project"

prepare() {
  : > "$GITHUB_ENV"
  : > "$GITHUB_OUTPUT"
  bash "$action_dir/prepare.sh"
}

prepare
[ -L deps ] && [ -L _build ]
grep -qx 'cache-hit=false' "$GITHUB_OUTPUT"
printf 'retained' > deps/marker
printf 'compiled' > _build/marker
rm deps _build
export MIX_VOLUME_HIT=true
prepare
grep -qx 'cache-hit=true' "$GITHUB_OUTPUT"
[ "$(cat deps/marker)" = retained ] && [ "$(cat _build/marker)" = compiled ]
echo 'ok: identical identity reuses dependency and build state'

for identity in v1-elixir-otp-lock-b v1-new-elixir-otp-lock-b v1-new-elixir-new-otp-lock-b; do
  printf 'obsolete' > deps/marker
  printf 'obsolete' > _build/marker
  rm deps _build
  export MIX_CACHE_IDENTITY="$identity"
  prepare
  grep -qx 'cache-hit=false' "$GITHUB_OUTPUT"
  [ ! -e deps/marker ] && [ ! -e _build/marker ]
  [ "$(cat "$RUNNER_TEMP/mix-cache/.mix-cache-identity")" = "$identity" ]
done
echo 'ok: lockfile and compiler changes invalidate private build state'

rm deps _build
rm "$RUNNER_TEMP/mix-cache/.mix-cache-identity"
printf 'legacy' > "$RUNNER_TEMP/mix-cache/deps/marker"
prepare
[ ! -e deps/marker ]
grep -qx 'cache-hit=false' "$GITHUB_OUTPUT"
echo 'ok: a missing identity cannot reuse legacy state'

rm deps _build
mkdir deps
printf 'untouched' > deps/existing
printf 'cached' > "$RUNNER_TEMP/mix-cache/deps/marker"
export MIX_CACHE_IDENTITY=different
if prepare; then echo 'Expected a nonempty path to fail' >&2; exit 1; fi
[ "$(cat deps/existing)" = untouched ]
[ "$(cat "$RUNNER_TEMP/mix-cache/deps/marker")" = cached ]
echo 'ok: populated checkout paths are rejected before cache mutation'
rm deps/existing
rmdir deps
ln -s "$fixture" deps
if prepare; then echo 'Expected an existing symlink to fail' >&2; exit 1; fi
[ -L deps ]
echo 'ok: existing symlinks are not replaced'
