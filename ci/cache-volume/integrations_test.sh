#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export CALL_LOG="$fixture/calls" PATH="$fixture:$PATH"
cat > "$fixture/tuist-cache-volume" <<'CLIENT'
#!/bin/bash
if [ "$1" = -h ]; then
  echo 'Usage of tuist-cache-volume:' >&2
  echo '  -key string' >&2
  echo '  -path value' >&2
  if [ -n "${CLIENT_SUPPORTS_SIZE-1}" ]; then
    echo '  -size string' >&2
    exit 0
  fi
  exit 2
fi
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
export BUILDKITE_PLUGIN_CONFIGURATION='{"volumes":[{"key":"shared","path":[".npm","cache $(literal)","~/.cache/pip"]},{"key":"single","path":["only"]}]}'
bash "$source_dir/buildkite/hooks/pre-command"
jq -se '.[0] == ["--key","shared","--path",".npm","--path","cache $(literal)","--path","~/.cache/pip"] and .[1] == ["--key","single","--path","only"] and length == 2' "$CALL_LOG" >/dev/null
echo 'ok: Buildkite passes every path of a volume to one client call'

rm "$CALL_LOG"
for config in '{}' '{"volumes":[]}' '{"volumes":[{"key":"ok","path":".ok"},{"key":"bad"}]}' '{"volumes":[{"key":"x","path":"a\nb"}]}' '{"volumes":[{"key":"x","path":[]}]}' '{"volumes":[{"key":"x","path":["a",""]}]}' '{"volumes":[{"key":"x","path":["a","b\nc"]}]}' '{"volumes":[{"key":"x","path":[1]}]}' '{"volumes":[{"key":"x","path":{"a":"b"}}]}' "$(jq -cn '{volumes: [range(9) | {key:"x",path:"p"}]}')" '{"volumes":[{"key":"ok","path":".ok"},{"key":"","path":"p"}]}' '{"volumes":[{"key":"ok","path":".ok"},{"path":"p","cache":"x"}]}' "$(jq -cn '{volumes: [{path: [range(17) | "p\(.)"]}]}')" '{"volumes":[{"key":"ok","path":".ok"},{"path":"p","size":50}]}' '{"volumes":[{"key":"ok","path":".ok"},{"key":"tuist-gradle","path":"p"}]}' '{"volumes":[{"key":"ok","path":".ok"},{"key":"Tuist-Mine","path":"p"}]}' '{"volumes":[{"key":"ok","path":".ok"},{"path":"p","size":"0gb"}]}' '{"volumes":[{"key":"ok","path":".ok"},{"path":"p","size":"101gb"}]}' '{"volumes":[{"key":"ok","path":".ok"},{"path":"p","size":"50"}]}' '{"volumes":[{"key":"ok","path":".ok"},{"path":"p","size":"50gib"}]}' '{"volumes":[{"key":"ok","path":".ok"},{"path":"p","size":"2.5gb"}]}'; do
  if BUILDKITE_PLUGIN_CONFIGURATION="$config" bash "$source_dir/buildkite/hooks/pre-command" > "$fixture/error" 2>&1; then
    echo 'FAIL: accepted invalid Buildkite configuration' >&2; exit 1
  fi
  [[ ! -e "$CALL_LOG" ]]
done
echo 'ok: Buildkite validates every entry before attachment'

for key in tuist-gradle Tuist-Mine; do
  BUILDKITE_PLUGIN_CONFIGURATION="{\"volumes\":[{\"key\":\"$key\",\"path\":\"p\"}]}" bash "$source_dir/buildkite/hooks/pre-command" > "$fixture/error" 2>&1 && exit 1
  grep -q 'reserved for Tuist' "$fixture/error"
done
BUILDKITE_PLUGIN_CONFIGURATION='{"volumes":[{"path":"p","size":"50"}]}' bash "$source_dir/buildkite/hooks/pre-command" > "$fixture/error" 2>&1 && exit 1
grep -q 'invalid cache volume size "50": use a whole number of GB from 1gb to 100gb, such as 50gb' "$fixture/error"
[[ ! -e "$CALL_LOG" ]]
echo 'ok: Buildkite explains reserved keys and invalid sizes'

export BUILDKITE_PLUGIN_CONFIGURATION="$(jq -cn '{volumes: [{path: [range(16) | "p\(.)"], size: "50GB"}, {key: "npm", path: ".npm", size: "5gb"}, {key: "pip", path: "pip"}]}')"
bash "$source_dir/buildkite/hooks/pre-command" > "$fixture/log" 2>&1
jq -se '.[0] == (["--key","tuist-default"] + [range(16) | "--path", "p\(.)"] + ["--size","50GB"]) and .[1] == ["--key","npm","--path",".npm","--size","5gb"] and .[2] == ["--key","pip","--path","pip"] and length == 3' "$CALL_LOG" >/dev/null
if grep -q 'does not support size' "$fixture/log"; then echo 'FAIL: unexpected warning' >&2; exit 1; fi
echo 'ok: Buildkite defaults the key and passes each volume size'

rm "$CALL_LOG"
CLIENT_SUPPORTS_SIZE= bash "$source_dir/buildkite/hooks/pre-command" > "$fixture/log" 2>&1
jq -se '.[0] == (["--key","tuist-default"] + [range(16) | "--path", "p\(.)"]) and .[1] == ["--key","npm","--path",".npm"] and length == 3' "$CALL_LOG" >/dev/null
[[ $(grep -c 'does not support size' "$fixture/log") == 1 ]]
echo 'ok: Buildkite warns once and attaches without sizes on an older client'
rm "$CALL_LOG"

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
if TUIST_VOLUME_KEY=cache TUIST_VOLUME_PATH='' bash -e "$fixture/gitlab.sh" > "$fixture/error" 2>&1; then
  echo 'FAIL: GitLab accepted missing inputs' >&2; exit 1
fi
[[ ! -e "$CALL_LOG" ]]
echo 'ok: GitLab rejects missing inputs before calling the client'

for key in '' ' '; do
  TUIST_VOLUME_KEY="$key" TUIST_VOLUME_PATH=cache bash -e "$fixture/gitlab.sh"
done
(unset TUIST_VOLUME_KEY; TUIST_VOLUME_PATH=cache bash -e "$fixture/gitlab.sh")
jq -se 'length == 3 and all(.[]; . == ["--key","tuist-default","--path","cache"])' "$CALL_LOG" >/dev/null
echo 'ok: GitLab attaches the default volume without a key'

rm "$CALL_LOG"
for key in tuist-gradle TUIST-mine; do
  if TUIST_VOLUME_KEY="$key" TUIST_VOLUME_PATH=cache bash -e "$fixture/gitlab.sh" > "$fixture/error" 2>&1; then
    echo 'FAIL: GitLab accepted a reserved key' >&2; exit 1
  fi
  grep -q 'reserved for Tuist' "$fixture/error"
done
[[ ! -e "$CALL_LOG" ]]
echo 'ok: GitLab rejects reserved keys before calling the client'

TUIST_VOLUME_PATH=cache TUIST_VOLUME_SIZE=' 50gb ' bash -e "$fixture/gitlab.sh" > "$fixture/log" 2>&1
CLIENT_SUPPORTS_SIZE= TUIST_VOLUME_PATH=cache TUIST_VOLUME_SIZE=50gb bash -e "$fixture/gitlab.sh" > "$fixture/log" 2>&1
jq -se 'length == 2 and .[0] == ["--key","tuist-default","--path","cache","--size","50gb"] and .[1] == ["--key","tuist-default","--path","cache"]' "$CALL_LOG" >/dev/null
grep -q 'does not support size' "$fixture/log"
echo 'ok: GitLab passes the size only to a client that supports it'

rm -f "$CALL_LOG"
TUIST_VOLUME_KEY=shared TUIST_VOLUME_PATH=$'  .npm\n\n\t~/.cache/pip  \r\n   \n cache $(literal) \n' bash -e "$fixture/gitlab.sh"
jq -se 'length == 1 and .[0] == ["--key","shared","--path",".npm","--path","~/.cache/pip","--path","cache $(literal)"]' "$CALL_LOG" >/dev/null
echo 'ok: GitLab passes each nonblank line as one trimmed path'

rm "$CALL_LOG"
if TUIST_VOLUME_KEY=cache TUIST_VOLUME_PATH=$' \n\t\n' bash -e "$fixture/gitlab.sh" > "$fixture/error" 2>&1; then
  echo 'FAIL: GitLab accepted blank paths' >&2; exit 1
fi
[[ ! -e "$CALL_LOG" ]]
grep -q 'at least one path' "$fixture/error"
echo 'ok: GitLab rejects blank paths before calling the client'
