#!/usr/bin/env bash
# Test when a deploy moves runner pools to a release's images.

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/runner-image-staging-gate.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

repo=ghcr.io/tuist/tuist-runner
old="sha256:$(printf 'a%.0s' {1..64})"
new="sha256:$(printf 'b%.0s' {1..64})"
old_stacked="sha256:$(printf 'c%.0s' {1..64})"
new_stacked="sha256:$(printf 'd%.0s' {1..64})"
announced_epoch=1792670400
announced_at=2026-10-22T12:00:00Z

golden() {
  local sum
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(printf '%s' "$1" | sha256sum)"
  else
    sum="$(printf '%s' "$1" | shasum -a 256)"
  fi
  echo "tuist.dev/golden-${sum:0:16}"
}

cat > "$scratch/kubectl" <<BASH
#!/usr/bin/env bash
case "\$2" in
  runnerpools.tuist.dev) cat "$scratch/pools.json" ;;
  nodes) cat "$scratch/nodes.json" ;;
  configmaps) cat "$scratch/announcements.json" ;;
  *) exit 1 ;;
esac
BASH
chmod +x "$scratch/kubectl"

cat > "$scratch/pools.json" <<JSON
{"items": [
  {"metadata": {"labels": {"tuist.dev/xcode-version": "26.6", "tuist.dev/runner-image-variant": "standalone"}}, "spec": {"image": "$repo@$old"}},
  {"metadata": {"labels": {"tuist.dev/xcode-version": "26.6", "tuist.dev/runner-image-variant": "standalone"}}, "spec": {"image": "$repo@$old"}},
  {"metadata": {"labels": {"tuist.dev/xcode-version": "26.6", "tuist.dev/runner-image-variant": "stacked"}}, "spec": {"image": "$repo@$old_stacked"}}
]}
JSON

# $1 staging annotation, $2 announced-at.
announce() {
  cat > "$scratch/announcements.json" <<JSON
{"items": [{"metadata": {"annotations": {"tuist.dev/runner-image-staging": "$1", "tuist.dev/runner-image-announced-at": "$2"}},
  "data": {"26.6.standalone": "$repo@$new", "26.6.stacked": "$repo@$new_stacked"}}]}
JSON
}

# Each argument is "<name>:<ready>:<unschedulable>:<image>,<image>…", the
# images whose goldens the Node advertises.
hosts() {
  local items=() name ready unschedulable images labels image
  for host in "$@"; do
    IFS=: read -r name ready unschedulable images <<< "$host"
    labels='{}'
    for image in ${images//,/ }; do
      labels="$(jq -c --arg key "$(golden "$image")" '. + {($key): "true"}' <<< "$labels")"
    done
    items+=("$(jq -cn --arg name "$name" --arg ready "$ready" --argjson unschedulable "$unschedulable" --argjson labels "$labels" \
      '{metadata: {name: $name, labels: $labels}, spec: {unschedulable: $unschedulable}, status: {conditions: [{type: "Ready", status: $ready}]}}')")
  done
  jq -cn '{items: $ARGS.positional | map(fromjson)}' --args "${items[@]}" > "$scratch/nodes.json"
}

# $1 expected standalone digest, $2 expected stacked digest, $3 description,
# optional $4 seconds since the announcement.
expect() {
  local actual
  actual="$(PATH="$scratch:$PATH" NOW=$((announced_epoch + ${4:-600})) bash "$SCRIPT" \
    "{\"26.6\": \"$new\"}" "{\"26.6\": \"$new_stacked\"}" 2>/dev/null)"
  local want
  want="$(jq -cn --arg d "$1" --arg s "$2" '{digests: {"26.6": $d}, stacked: {"26.6": $s}}')"
  if [ "$actual" != "$want" ]; then
    echo "Expected $want for $3, got $actual." >&2
    exit 1
  fi
}

announce wait "$announced_at"

hosts "b03:True:false:$repo@$old,$repo@$new" "b04:True:false:$repo@$old" "b05:True:false:$repo@$old_stacked"
expect "$old" "$old_stacked" "hosts that serve the pools without the new goldens"

hosts "b03:True:false:$repo@$old,$repo@$new" "b04:True:false:$repo@$old" "b05:True:false:$repo@$old_stacked,$repo@$new_stacked"
expect "$old" "$new_stacked" "the stacked image staged and the standalone one not"

hosts "b03:True:false:$repo@$old,$repo@$new" "b04:False:false:$repo@$old" "b05:True:true:$repo@$old_stacked"
expect "$new" "$new_stacked" "the only hosts missing an image NotReady or cordoned"

hosts "b06:True:false:"
expect "$new" "$new_stacked" "no host holding the current images"

hosts "b04:True:false:$repo@$old" "b05:True:false:$repo@$old_stacked"
expect "$new" "$new_stacked" "an announcement older than the timeout" 3600

announce skip "$announced_at"
expect "$new" "$new_stacked" "a release that skips staging"

announce wait ""
expect "$new" "$new_stacked" "an announcement without a time"

echo '{"items": []}' > "$scratch/announcements.json"
expect "$new" "$new_stacked" "no announcement of the new images"

echo "All runner image staging gate tests passed."
