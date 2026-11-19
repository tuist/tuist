#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT
export JIT_OUTPUT_PATH="$fixtures/jit"
awk '/^stage_cache_grant\(\)/ { copying=1 } copying { print } copying && /^}/ { exit }' dispatch-poll.sh |
  sed "s|/tmp/dispatch.json|$fixtures/dispatch.json|g" > "$fixtures/stage.sh"
source "$fixtures/stage.sh"
printf '{"cache_signing_grant":"signed.runner.grant"}' > "$fixtures/dispatch.json"
stage_cache_grant > "$fixtures/output"
test "$(cat "$JIT_OUTPUT_PATH.cache-grant")" = signed.runner.grant
! grep -q 'signed.runner.grant' "$fixtures/output"
printf '{}' > "$fixtures/dispatch.json"
stage_cache_grant
test ! -e "$JIT_OUTPUT_PATH.cache-grant"
echo 'ok: dispatch stages the grant without logging it and clears it for untrusted jobs'
