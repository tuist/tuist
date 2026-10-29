#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export IMAGE_TEST_WORK="$work"
mkdir "$work/bin" "$work/daemonsets"
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$IMAGE_TEST_WORK/calls"
[[ "${IMAGE_TEST_FAIL:-}" != read ]] || exit 1
name=""
previous=""
for arg in "$@"; do
  [[ "$previous" != daemonset ]] || name="$arg"
  if [[ "$arg" == tuist.dev/linux-image-prepull=* ]]; then name="${arg#*=}"; fi
  previous="$arg"
done
if [[ "$*" == *'get runnerpools.tuist.dev'* ]]; then
  cat "$IMAGE_TEST_WORK/current.json"
elif [[ "$*" == *'get nodes'* ]]; then
  cat "$IMAGE_TEST_WORK/nodes.json"
elif [[ "$*" == *'apply -f'* ]]; then
  [[ "${IMAGE_TEST_FAIL:-}" != apply ]] || exit 1
  cp "${@: -1}" "$IMAGE_TEST_WORK/applied.json"
  name="$(jq -r .metadata.name "$IMAGE_TEST_WORK/applied.json")"
  if [[ ! -f "$IMAGE_TEST_WORK/daemonsets/$name.json" ]]; then
    jq '.metadata.uid="current-ds" | .metadata.creationTimestamp="2026-10-27T00:00:00Z"' "$IMAGE_TEST_WORK/applied.json" > "$IMAGE_TEST_WORK/daemonsets/$name.json"
  fi
elif [[ "$*" == *'get daemonsets '* ]]; then
  [[ "${IMAGE_TEST_FAIL:-}" != cleanup ]] || exit 1
  files=("$IMAGE_TEST_WORK"/daemonsets/*.json)
  if [[ -f "${files[0]}" ]]; then jq -s '{items:.}' "${files[@]}"; else echo '{"items":[]}'; fi
elif [[ "$*" == *'get daemonset '* ]]; then
  cat "$IMAGE_TEST_WORK/daemonsets/$name.json"
elif [[ "$*" == *'get pods '* ]]; then
  jq --slurpfile ds "$IMAGE_TEST_WORK/daemonsets/$name.json" '
    .items |= map(.spec.containers = $ds[0].spec.template.spec.containers
      | .spec.runtimeClassName = $ds[0].spec.template.spec.runtimeClassName)
  ' "$IMAGE_TEST_WORK/pods.json" | jq "${IMAGE_TEST_POD_MUTATION:-.}"
elif [[ "$*" == *'delete daemonset '* ]]; then
  rm "$IMAGE_TEST_WORK/daemonsets/$name.json"
else
  echo "Unexpected kubectl call: $*" >&2; exit 1
fi
STUB
cat > "$work/bin/sleep" <<'STUB'
#!/usr/bin/env bash
if [[ "${LINUX_IMAGE_STAGING_WAIT_SECONDS:-0}" != 0 ]]; then
  echo sleep >> "$IMAGE_TEST_WORK/calls"
  if [[ "${IMAGE_TEST_EVENTUALLY_READY:-}" == true ]]; then
    cp "$IMAGE_TEST_WORK/ready-pods.json" "$IMAGE_TEST_WORK/pods.json"
  else
    /bin/sleep "$1"
  fi
  exit 0
fi
echo 'Image staging must not poll or wait' >&2
exit 1
STUB
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
image="ghcr.io/tuist/tuist-linux-runner@sha256:$(printf 'a%.0s' {1..64})"
old="ghcr.io/tuist/tuist-linux-runner@sha256:$(printf 'b%.0s' {1..64})"
jq -n --arg image "$image" '[
  {kind:"RunnerPool",metadata:{namespace:"runners",name:"shape"},spec:{os:"linux",image:$image,fleetSelector:"runners-linux",runtimeClass:"kata-qemu"}},
  {kind:"RunnerPool",metadata:{namespace:"runners",name:"explicit"},spec:{os:"linux",image:$image,fleetSelector:"runners-linux",runtimeClass:"kata-qemu"}},
  {kind:"RunnerPool",metadata:{namespace:"macs",name:"mac"},spec:{os:"darwin",image:"mac:tag"}}
]' > "$work/render.json"
jq --arg old "$old" '{items: map(select(.spec.os=="linux") | .spec.image=$old)}' "$work/render.json" > "$work/old.json"
jq -n '{items:["node-a","node-b"] | map({metadata:{name:.},spec:{},status:{conditions:[{type:"Ready",status:"True"}]}})}' > "$work/ready-nodes.json"
jq -n '{items:["node-a","node-b"] | map({metadata:{ownerReferences:[{uid:"current-ds",controller:true}]},spec:{nodeName:.},status:{phase:"Running",containerStatuses:[{name:"pull",ready:true,state:{running:{}}}]}})}' > "$work/ready-pods.json"
reset() {
  rm -f "$work/daemonsets/"*.json
  cp "$work/old.json" "$work/current.json"
  cp "$work/ready-nodes.json" "$work/nodes.json"
  cp "$work/ready-pods.json" "$work/pods.json"
  : > "$work/calls"
}
run() {
  NOW="${TEST_NOW:-1793059800}" bash "$root/.github/scripts/linux-runner-image-prepare.sh" "${1:-$work/render.json}" tuist staging > "$work/output.json" 2> "$work/log"
}
held() { jq -e --arg old "$old" '.runnersFleetLinux.imageHolds == {shape:$old,explicit:$old}' "$work/output.json" >/dev/null; }
moving() { jq -e '.runnersFleetLinux.imageHolds == {}' "$work/output.json" >/dev/null; }

# Pending images are held immediately, not waited on or treated as failures.
# The helper survives the command and a later invocation promotes once ready.
reset
jq '.items[].status.phase="Pending"' "$work/ready-pods.json" > "$work/pods.json"
run
held
test "$(grep -c 'apply -f' "$work/calls")" = 1
test "$(grep -c 'get pods' "$work/calls")" = 1
test -n "$(ls "$work/daemonsets/")"
if grep -q 'delete daemonset' "$work/calls"; then echo 'Deleted background preparation' >&2; exit 1; fi
run
held
cp "$work/ready-pods.json" "$work/pods.json"
run
moving
# Keep readiness proof until the pools actually move, even if Helm rolls back.
test -n "$(ls "$work/daemonsets/")"
jq '{items:map(select(.spec.os=="linux"))}' "$work/render.json" > "$work/current.json"
run
moving
test -z "$(ls "$work/daemonsets/")"

# The same target's first creation time bounds holds across deployments.
reset
jq '.items[].status.phase="Pending"' "$work/ready-pods.json" > "$work/pods.json"
run
held
TEST_NOW=1793062800 run
moving
test -n "$(ls "$work/daemonsets/")"

# Exact image/runtime, owner, per-host presence and running state are required.
for mutation in \
  'del(.items[1])' \
  '.items[1].spec.nodeName="node-a"' \
  '.items[1].metadata.ownerReferences[0].uid="old-ds"' \
  '.items[1].metadata.deletionTimestamp="2026-10-27T00:00:00Z"' \
  '.items[1].status.phase="Pending"' \
  '.items[1].status.containerStatuses[0].ready=false' \
  '.items[1].status.containerStatuses[0].state={waiting:{reason:"ImagePullBackOff"}}' \
  '.items[1].spec.containers[0].image="old:image"' \
  '.items[1].spec.runtimeClassName="other"'; do
  reset
  IMAGE_TEST_POD_MUTATION="$mutation" run
  held
done

# Ignore unavailable hosts; no serving hosts and first installs move normally.
for mutation in '.items[1].spec.unschedulable=true' '.items[1].status.conditions[0].status="False"'; do
  reset
  jq "$mutation" "$work/ready-nodes.json" > "$work/nodes.json"
  jq 'del(.items[1])' "$work/ready-pods.json" > "$work/pods.json"
  run
  moving
done
for nodes in '{"items":[]}' '{"items":[{"spec":{"unschedulable":true}}]}'; do
  reset
  echo "$nodes" > "$work/nodes.json"
  run
  moving
  test ! -f "$work/daemonsets/$(jq -r .metadata.name "$work/applied.json").json"
done
reset
echo '{"items":[]}' > "$work/current.json"
run
moving
if grep -q 'apply -f' "$work/calls"; then echo 'Applied a helper for first install' >&2; exit 1; fi

# Native and managed Kata share one image store; custom runtimes remain intact.
reset
jq '.[1].spec.runtimeClass=""' "$work/render.json" > "$work/shared.json"
run "$work/shared.json"
test "$(grep -c 'apply -f' "$work/calls")" = 1
jq -e '.spec.template.spec | .runtimeClassName == null and .automountServiceAccountToken == false and .volumes == null and .containers[0].resources.requests.memory == "16Mi"' "$work/applied.json" >/dev/null
reset
jq '.[1].spec.runtimeClass="custom-runtime"' "$work/render.json" > "$work/custom.json"
run "$work/custom.json"
test "$(grep -c 'apply -f' "$work/calls")" = 2
jq -se 'any(.[]; .spec.template.spec.runtimeClassName == "custom-runtime")' "$work/daemonsets/"*.json >/dev/null

# Hold each pool's own current image, without overriding a new pool or macOS.
reset
jq --arg image "$image" '.items[1].spec.image=$image' "$work/old.json" > "$work/current.json"
jq '.items[].status.phase="Pending"' "$work/ready-pods.json" > "$work/pods.json"
run
jq -e --arg old "$old" '.runnersFleetLinux.imageHolds == {shape:$old}' "$work/output.json" >/dev/null

# Superseded helpers are cleaned only within this release's ownership scope.
cp "$work/applied.json" "$work/foreign.json"
jq '.metadata.name="foreign" | .metadata.labels["tuist.dev/linux-image-staging-owner"]="someone-else"' "$work/foreign.json" > "$work/daemonsets/foreign.json"
echo '[]' > "$work/off.json"
run "$work/off.json"
moving
test "$(ls "$work/daemonsets/")" = foreign.json

# Reads/applies fail for the caller to warn and fail open, just like macOS.
for operation in read apply; do
  reset
  if IMAGE_TEST_FAIL="$operation" run; then echo "Ignored $operation failure" >&2; exit 1; fi
done
reset
jq '.items[].status.phase="Pending"' "$work/ready-pods.json" > "$work/pods.json"
IMAGE_TEST_FAIL=cleanup run
held

# Canary waits within the same deployment, including first installs and pools
# already naming the candidate. It never accepts old DaemonSet age as proof.
reset
jq '.items[].status.phase="Pending"' "$work/ready-pods.json" > "$work/pods.json"
LINUX_IMAGE_STAGING_WAIT_SECONDS=10 IMAGE_TEST_EVENTUALLY_READY=true run
moving
test "$(grep -c 'get pods' "$work/calls")" = 2
test "$(grep -c 'get nodes' "$work/calls")" = 2
for current in '{"items":[]}' "$(jq '{items:map(select(.spec.os=="linux"))}' "$work/render.json")"; do
  reset
  echo "$current" > "$work/current.json"
  LINUX_IMAGE_STAGING_WAIT_SECONDS=10 run
  moving
  test "$(grep -c 'apply -f' "$work/calls")" = 1
done
for failure in pending expired no-hosts wrong-image; do
  reset
  case "$failure" in
    pending|expired) jq '.items[].status.phase="Pending"' "$work/ready-pods.json" > "$work/pods.json" ;;
    no-hosts) echo '{"items":[]}' > "$work/nodes.json" ;;
    wrong-image) export IMAGE_TEST_POD_MUTATION='.items[1].spec.containers[0].image="old:image"' ;;
  esac
  if TEST_NOW=1793062800 LINUX_IMAGE_STAGING_WAIT_SECONDS=1 run; then
    echo "Canary accepted $failure" >&2; exit 1
  fi
  unset IMAGE_TEST_POD_MUTATION
  grep -q 'refusing to qualify an old image' "$work/log"
done
for operation in read apply; do
  reset
  if IMAGE_TEST_FAIL="$operation" LINUX_IMAGE_STAGING_WAIT_SECONDS=10 run; then
    echo "Canary ignored $operation failure" >&2; exit 1
  fi
done

# Release staging retargets this release's live digest pools, and the
# deploy's own check then adopts its helper and moves them.
stage() {
  NOW=1793059800 LINUX_IMAGE_STAGING_WAIT_SECONDS="${1:-10}" bash "$root/.github/scripts/linux-runner-image-stage.sh" "$image" tuist staging 2> "$work/log"
}
jq --arg old "$old" '.items |= (map(.metadata.annotations = {"meta.helm.sh/release-name":"tuist","meta.helm.sh/release-namespace":"staging"})
  + [.[0] | .metadata.name = "tag-pinned" | .spec.image = "ghcr.io/tuist/tuist-linux-runner:sha-0123"]
  + [.[0] | .metadata.name = "other-release" | .metadata.annotations["meta.helm.sh/release-name"] = "other"])' "$work/old.json" > "$work/live.json"
reset
cp "$work/live.json" "$work/current.json"
jq '.items[].status.phase="Pending"' "$work/ready-pods.json" > "$work/pods.json"
IMAGE_TEST_EVENTUALLY_READY=true stage
test "$(grep -c 'apply -f' "$work/calls")" = 1
jq -e --arg image "$image" '.spec.template.spec.containers[0].image == $image' "$work/applied.json" >/dev/null
staged="$(ls "$work/daemonsets/")"
: > "$work/calls"
run
moving
test "$(ls "$work/daemonsets/")" = "$staged"
# Hosts not ready in time fail for the caller to warn; the deploy then holds.
reset
cp "$work/live.json" "$work/current.json"
jq '.items[].status.phase="Pending"' "$work/ready-pods.json" > "$work/pods.json"
if stage 1; then echo 'Staging accepted unready hosts' >&2; exit 1; fi
run
held
# Fleets without serving hosts and releases without digest pools stage nothing.
for case in no-hosts no-pools; do
  reset
  cp "$work/live.json" "$work/current.json"
  case "$case" in
    no-hosts) echo '{"items":[]}' > "$work/nodes.json" ;;
    no-pools) jq '.items |= map(.metadata.annotations["meta.helm.sh/release-name"] = "other")' "$work/live.json" > "$work/current.json" ;;
  esac
  stage
  if grep -q 'apply -f' "$work/calls"; then echo "Staged with $case" >&2; exit 1; fi
done
echo 'Linux staging: background holds, release staging and bounded, fail-closed canary preparation checks passed.'
