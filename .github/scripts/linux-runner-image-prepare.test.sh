#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export IMAGE_TEST_WORK="$work"
mkdir "$work/bin"
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$IMAGE_TEST_WORK/calls"
if [[ "$*" == *'get nodes'* ]]; then
  cat "$IMAGE_TEST_WORK/nodes.json"
elif [[ "$*" == *'apply -f'* ]]; then
  cp "${@: -1}" "$IMAGE_TEST_WORK/applied.json"
elif [[ "$*" == *'get daemonset'* ]]; then
  printf 'current-ds'
elif [[ "$*" == *'get pods'* ]]; then
  jq --slurpfile ds "$IMAGE_TEST_WORK/applied.json" '
    .items |= map(.spec.containers = $ds[0].spec.template.spec.containers
      | .spec.runtimeClassName = $ds[0].spec.template.spec.runtimeClassName)
  ' "$IMAGE_TEST_WORK/pods.json"
fi
STUB
chmod +x "$work/bin/kubectl"
export PATH="$work/bin:$PATH"
image="ghcr.io/tuist/tuist-linux-runner@sha256:$(printf 'a%.0s' {1..64})"
jq -n --arg image "$image" '[
  {kind:"RunnerPool",metadata:{namespace:"runners"},spec:{os:"linux",image:$image,fleetSelector:"runners-linux",runtimeClass:"kata-qemu"}},
  {kind:"RunnerPool",metadata:{namespace:"runners"},spec:{os:"linux",image:$image,fleetSelector:"runners-linux",runtimeClass:"kata-qemu"}},
  {kind:"RunnerPool",metadata:{namespace:"macs"},spec:{os:"darwin",image:"mac:tag"}}
]' > "$work/render.json"
jq -n '{items:["node-a","node-b"] | map({metadata:{name:.},spec:{},status:{conditions:[{type:"Ready",status:"True"}]}})}' > "$work/ready-nodes.json"
jq -n '{items:["node-a","node-b"] | map({
  metadata:{ownerReferences:[{uid:"current-ds",controller:true}]},spec:{nodeName:.},
  status:{phase:"Running",containerStatuses:[{name:"pull",ready:true,state:{running:{}}}]}
})}' > "$work/ready-pods.json"
reset() {
  cp "$work/ready-nodes.json" "$work/nodes.json"
  cp "$work/ready-pods.json" "$work/pods.json"
  : > "$work/calls"
}
run() {
  LINUX_IMAGE_PREPARE_TIMEOUT_SECONDS=0 bash "$root/.github/scripts/linux-runner-image-prepare.sh" "${1:-$work/render.json}" > "$work/output" 2>&1
}
reset
run
test "$(grep -c 'apply -f' "$work/calls")" = 1
grep -q 'delete -f.*--ignore-not-found --wait=false' "$work/calls"
jq -e --arg image "$image" '.spec.template.spec |
  .containers[0].image == $image and .containers[0].imagePullPolicy == "IfNotPresent"
  and .containers[0].command == ["/bin/sleep","infinity"]
  and .runtimeClassName == "kata-qemu" and .automountServiceAccountToken == false
  and .priorityClassName == null and .volumes == null
  and .nodeSelector == {"kubernetes.io/os":"linux","kubernetes.io/arch":"amd64","node.cluster.x-k8s.io/pool":"runners-linux"}
  and (.tolerations | length == 2)' "$work/applied.json" >/dev/null

# A duplicate on one node, old owner, terminating pod or pending pull must
# never satisfy the gate, even if aggregate counts look healthy.
for mutation in \
  'del(.items[1])' \
  '.items[1].spec.nodeName = "node-a"' \
  '.items[1].metadata.ownerReferences[0].uid = "old-ds"' \
  '.items[1].metadata.deletionTimestamp = "2026-10-27T00:00:00Z"' \
  '.items[1].status.phase = "Pending"' \
  '.items[1].status.containerStatuses[0].ready = false' \
  '.items[1].status.containerStatuses[0].state = {waiting:{reason:"ImagePullBackOff"}}'; do
  reset
  jq "$mutation" "$work/ready-pods.json" > "$work/pods.json"
  if run; then echo "Accepted unstaged host: $mutation" >&2; exit 1; fi
  grep -q 'runner pools have not been switched' "$work/output"
  grep -q 'delete -f' "$work/calls"
done

# Unusable hosts are excluded, but zero usable hosts on an existing fleet
# does not pass vacuously. A new host seen during the wait must also stage.
for mutation in '.items[1].spec.unschedulable = true' '.items[1].status.conditions[0].status = "False"'; do
  reset
  jq "$mutation" "$work/ready-nodes.json" > "$work/nodes.json"
  jq 'del(.items[1])' "$work/ready-pods.json" > "$work/pods.json"
  run
done
reset
jq '.items[].spec.unschedulable = true' "$work/ready-nodes.json" > "$work/nodes.json"
if run; then echo 'Accepted zero usable hosts' >&2; exit 1; fi
reset
jq '.items += [.items[0] | .metadata.name = "new-node"]' "$work/ready-nodes.json" > "$work/nodes.json"
if run; then echo 'Accepted an unstaged new host' >&2; exit 1; fi

# First installation, disabled Linux fleet, and invalid mutable references.
reset
echo '{"items":[]}' > "$work/nodes.json"
run
if grep -q 'apply -f' "$work/calls"; then echo 'Mutated a fleet with no hosts' >&2; exit 1; fi
reset
echo '[]' > "$work/off.json"
run "$work/off.json"
test ! -s "$work/calls"
reset
jq 'map(select(.spec.os == "linux") | .spec.image = "runner:mutable")' "$work/render.json" > "$work/tag.json"
if run "$work/tag.json"; then echo 'Accepted mutable image' >&2; exit 1; fi
if grep -q 'apply -f' "$work/calls"; then echo 'Applied a mutable image' >&2; exit 1; fi

# Native pools keep the default runtime. Multiple images/fleets get distinct
# DaemonSets rather than checking only whichever shape happened to be first.
reset
jq 'map(select(.spec.os == "linux") | del(.spec.runtimeClass))' "$work/render.json" > "$work/native.json"
run "$work/native.json"
jq -e '.spec.template.spec.runtimeClassName == null' "$work/applied.json" >/dev/null
reset
jq '.[1].spec.fleetSelector = "other-fleet"' "$work/render.json" > "$work/multiple.json"
run "$work/multiple.json"
test "$(grep -c 'apply -f' "$work/calls")" = 2

# Exercise wrong-image/runtime rejection directly (the fake kubectl otherwise
# fills these from the applied DaemonSet).
jq --slurpfile ds "$work/applied.json" '.items |= map(.spec.containers = $ds[0].spec.template.spec.containers | .spec.runtimeClassName = "kata-qemu")' "$work/ready-pods.json" > "$work/matching.json"
for mutation in '.items[0].spec.containers[0].image = "old:image"' '.items[0].spec.runtimeClassName = "other"'; do
  jq "$mutation" "$work/matching.json" > "$work/wrong.json"
  if jq -e --arg uid current-ds --slurpfile manifest "$work/applied.json" --slurpfile pods "$work/wrong.json" \
    -f "$root/.github/scripts/linux-runner-image-ready.jq" "$work/ready-nodes.json" >/dev/null; then
    echo "Accepted wrong pod: $mutation" >&2; exit 1
  fi
done
echo 'Linux image preparation: readiness, failure, cleanup, deduplication, runtime and first-install checks passed.'
