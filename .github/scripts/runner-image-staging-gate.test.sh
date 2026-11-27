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

# Reads come from the fixtures; writes are appended to writes.log as
# "<verb> <namespace> <object or patch JSON>".
cat > "$scratch/kubectl" <<BASH
#!/usr/bin/env bash
case " \$* " in
  *" get runnerpools.tuist.dev "*) cat "$scratch/pools.json" ;;
  *" get nodes "*) cat "$scratch/nodes.json" ;;
  *" get configmaps "*) cat "$scratch/announcements.json" ;;
  *" patch configmap tuist-upcoming-runner-images "*)
    ns="\$(sed -n 's/.*--namespace \\([^ ]*\\).*/\\1/p' <<< "\$*")"
    echo "patch \$ns \${@: -1}" >> "$scratch/writes.log" ;;
  *" create -f - "*) echo "create - \$(cat)" >> "$scratch/writes.log" ;;
  *) exit 1 ;;
esac
BASH
chmod +x "$scratch/kubectl"

cat > "$scratch/pools.json" <<JSON
{"items": [
  {"metadata": {"namespace": "tuist-runners", "labels": {"tuist.dev/xcode-version": "26.6", "tuist.dev/runner-image-variant": "standalone"}}, "spec": {"image": "$repo@$old"}},
  {"metadata": {"namespace": "tuist-runners", "labels": {"tuist.dev/xcode-version": "26.6", "tuist.dev/runner-image-variant": "standalone"}}, "spec": {"image": "$repo@$old"}},
  {"metadata": {"namespace": "tuist-runners", "labels": {"tuist.dev/xcode-version": "26.6", "tuist.dev/runner-image-variant": "stacked"}}, "spec": {"image": "$repo@$old_stacked"}}
]}
JSON

# $1 staging annotation, $2 announced-at, optional $3 the
# announced-at-by-image JSON, optional $4 the stacked digest it names.
announce() {
  jq -cn --arg staging "$1" --arg at "$2" --arg by_image "${3:-}" \
    --arg standalone "$repo@$new" --arg stacked "$repo@${4:-$new_stacked}" '{items: [{
      metadata: {namespace: "tuist-runners", name: "tuist-upcoming-runner-images", annotations: ({
        "tuist.dev/runner-image-staging": $staging, "tuist.dev/runner-image-announced-at": $at}
        + if $by_image == "" then {} else {"tuist.dev/runner-image-announced-at-by-image": $by_image} end)},
      data: {"26.6.standalone": $standalone, "26.6.stacked": $stacked}}]}' > "$scratch/announcements.json"
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
  : > "$scratch/writes.log"
  actual="$(PATH="$scratch:$PATH" NOW=$((announced_epoch + ${4:-600})) bash "$SCRIPT" \
    "{\"26.6\": \"$new\"}" "{\"26.6\": \"$new_stacked\"}" 2>/dev/null)"
  local want
  want="$(jq -cn --arg d "$1" --arg s "$2" '{digests: {"26.6": $d}, stacked: {"26.6": $s}}')"
  if [ "$actual" != "$want" ]; then
    echo "Expected $want for $3, got $actual." >&2
    exit 1
  fi
}

# $1 verb, $2 namespace, $3 key, $4 image, $5 epoch the key's time names.
expect_write() {
  if ! grep "^$1 $2 " "$scratch/writes.log" | cut -d' ' -f3- | jq -e --arg key "$3" --arg image "$4" --argjson at "$5" '
    .data[$key] == $image
    and .metadata.labels["tuist.dev/upcoming-runner-images"] == "true"
    and (.metadata.annotations["tuist.dev/runner-image-announced-at-by-image"] | fromjson | .[$key]) == ($at | todate)' \
    >/dev/null 2>&1; then
    echo "Expected a $1 in $2 naming $3=$4 at $5, got: $(cat "$scratch/writes.log")" >&2
    exit 1
  fi
}

# $1 description.
expect_no_writes() {
  if [ -s "$scratch/writes.log" ]; then
    echo "Expected no announcement for $1, got: $(cat "$scratch/writes.log")" >&2
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

# The hour counts from when each key named its digest, not from the
# ConfigMap's latest write.
announce wait "$announced_at" "{\"26.6.stacked\": \"2026-10-22T12:50:00Z\"}"
expect "$new" "$old_stacked" "a stacked image named 50 minutes ago and a standalone one an hour ago" 3600
expect_no_writes "keys every announcement already names"

# A release that announced one digest and then moved its tag to another
# (2026-11-26): the deploy's digest is unnamed, so the gate names it and holds.
announce wait "$announced_at" "" "$old_stacked"
expect "$new" "$old_stacked" "an announcement naming another stacked digest" 7200
expect_write patch tuist-runners "26.6.stacked" "$repo@$new_stacked" "$((announced_epoch + 7200))"

announce skip "$announced_at"
expect "$new" "$new_stacked" "a release that skips staging"

announce wait ""
expect "$new" "$new_stacked" "an announcement without a time"

echo '{"items": []}' > "$scratch/announcements.json"
expect "$old" "$old_stacked" "no announcement of the new images"
expect_write create - "26.6.standalone" "$repo@$new" "$((announced_epoch + 600))"
expect_write patch tuist-runners "26.6.stacked" "$repo@$new_stacked" "$((announced_epoch + 600))"

# A cluster the gate cannot read fails it, so the deploy moves the pools.
printf '#!/usr/bin/env bash\nexit 1\n' > "$scratch/kubectl"
if PATH="$scratch:$PATH" bash "$SCRIPT" "{\"26.6\": \"$new\"}" "{\"26.6\": \"$new_stacked\"}" >/dev/null 2>&1; then
  echo "Expected the gate to fail when the cluster cannot be read." >&2
  exit 1
fi

echo "All runner image staging gate tests passed."
