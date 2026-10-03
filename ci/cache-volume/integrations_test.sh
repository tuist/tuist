#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export CALL_LOG="$fixture/calls" PATH="$fixture:$PATH"
cat > "$fixture/tuist-cache-volume" <<'CLIENT'
#!/bin/bash
jq -cn --args '$ARGS.positional' -- "$@" >> "$CALL_LOG"
exit "${CLIENT_EXIT:-0}"
CLIENT
chmod +x "$fixture/tuist-cache-volume"
cd "$fixture"

export BUILDKITE_PLUGIN_CONFIGURATION='{"volumes":[{"key":"gradle;$(touch should-not-exist)","path":"cache directory"},{"key":"npm","path":".npm"}]}'
bash "$source_dir/buildkite/hooks/pre-command"
jq -se '.[0] == ["--key","gradle;$(touch should-not-exist)","--path","cache directory"] and .[1] == ["--key","npm","--path",".npm"] and length == 2' "$CALL_LOG" >/dev/null
[[ ! -e should-not-exist ]]
echo 'ok: Buildkite mounts multiple volumes with literal arguments'

rm "$CALL_LOG"
for config in '{}' '{"volumes":[]}' '{"volumes":[{"key":"ok","path":".ok"},{"key":"bad"}]}' '{"volumes":[{"key":"x","path":"a\nb"}]}' "$(jq -cn '{volumes: [range(9) | {key:"x",path:"p"}]}')"; do
  if BUILDKITE_PLUGIN_CONFIGURATION="$config" bash "$source_dir/buildkite/hooks/pre-command" > "$fixture/error" 2>&1; then
    echo 'FAIL: accepted invalid Buildkite configuration' >&2; exit 1
  fi
  [[ ! -e "$CALL_LOG" ]]
done
echo 'ok: Buildkite validates every entry before attachment'

export BUILDKITE_PLUGIN_CONFIGURATION='{"volumes":[{"key":"one","path":".one"},{"key":"two","path":".two"}]}'
status=0
CLIENT_EXIT=7 bash "$source_dir/buildkite/hooks/pre-command" || status=$?
[[ "$status" == 7 && $(jq -s length "$CALL_LOG") == 1 ]]
echo 'ok: a client failure stops later mounts'

bash "$source_dir/buildkite/package.sh" "$fixture/package"
[[ -x "$fixture/package/hooks/pre-command" ]]
[[ $(cat "$fixture/package/SOURCE_COMMIT") == "$(git -C "$source_dir" rev-parse HEAD)" ]]
rm "$CALL_LOG"
bash "$fixture/package/hooks/pre-command"
[[ -s "$CALL_LOG" ]]
echo 'ok: Buildkite package runs independently with an executable hook'

# Run the shell block from the actual distributed GitLab template.
sed -n 's/^      //p' "$source_dir/gitlab/cache-volume.yml" > "$fixture/gitlab.sh"
[[ -s "$fixture/gitlab.sh" ]]
rm "$CALL_LOG"
TUIST_VOLUME_KEY=cache TUIST_VOLUME_PATH='cache $(literal)' bash -e "$fixture/gitlab.sh"
jq -se 'length == 1 and .[0] == ["--key","cache","--path","cache $(literal)"]' "$CALL_LOG" >/dev/null
echo 'ok: GitLab passes literal key and path arguments'

rm "$CALL_LOG"
if TUIST_VOLUME_KEY='' TUIST_VOLUME_PATH=cache bash -e "$fixture/gitlab.sh" > "$fixture/error" 2>&1; then
  echo 'FAIL: GitLab accepted missing inputs' >&2; exit 1
fi
[[ ! -e "$CALL_LOG" ]]
echo 'ok: GitLab rejects missing inputs before calling the client'
