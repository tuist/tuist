#!/usr/bin/env bash
# Tests sandboxd-upgrade.sh against a fake kubectl: which Pods upgrade in
# place, which are replaced, and that a handover only follows an armed
# daemon.

set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/sandboxd-upgrade.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

repo=ghcr.io/tuist/sandboxd
old_id=containerd://$(printf 'a%.0s' $(seq 64))
config=$'SERVER_URL=http://server\nLOG_LEVEL=info\n'
config_sum=$(printf '%s' "$config" | sha256sum | cut -d' ' -f1)
digest=sha256:$(printf 'd%.0s' $(seq 64))

# template <daemon tag> <vmm tag>
template() {
  jq -cn --arg d "$repo:$1" --arg v "$repo:$2" '{
    metadata: {labels: {"app.kubernetes.io/name": "sandboxd"}},
    spec: {
      containers: [{name: "sandboxd", image: $d}, {name: "vmm", image: $v}],
      volumes: [{name: "config", configMap: {name: "sandboxd-config"}}]}}'
}

# scenario <pod's daemon tag> <pod's vmm tag> <arms: yes|no> [loaded config
# sum, default the ConfigMap's]; the
# DaemonSet always wants daemon sha-new and vmm sha-vmm. POD_IMAGE overrides
# the Pod's daemon image, IMAGE_ID the image it runs (default
# $repo@$digest), LAZY how many restores the daemon reports streaming disks
# (one fewer on each read), BUSY how many sandboxes it holds (one fewer on
# each read) and IDLE_WAIT the replacement's wait for none.
scenario() {
  state="$scratch/state"
  rm -rf "$state"
  mkdir -p "$state/bin"
  local want have
  want=$(template sha-new sha-vmm)
  have=$(template "$1" "$2")
  jq -n --argjson t "$want" '{metadata: {uid: "ds-uid"}, spec: {selector: {matchLabels: {"app.kubernetes.io/name": "sandboxd"}}, template: $t}}' > "$state/ds.json"
  jq -n --argjson old "$have" --argjson new "$want" '{items: [
    {metadata: {labels: {"controller-revision-hash": "old"}, ownerReferences: [{uid: "ds-uid"}]}, revision: 1, data: {spec: {template: ($old + {"$patch": "replace"})}}},
    {metadata: {labels: {"controller-revision-hash": "new"}, ownerReferences: [{uid: "ds-uid"}]}, revision: 2, data: {spec: {template: ($new + {"$patch": "replace"})}}}]}' > "$state/revisions.json"
  local hash=old
  [ "$1" = sha-new ] && [ "$2" = sha-vmm ] && hash=new
  [ -n "${POD_IMAGE:-}" ] && have=$(jq -c --arg i "$POD_IMAGE" '.spec.containers[0].image = $i' <<< "$have")
  jq -n --argjson t "$have" --arg id "$old_id" --arg h "$hash" --arg iid "${IMAGE_ID-$repo@$digest}" '{items: [
    {metadata: {name: "sandboxd-x", labels: {"controller-revision-hash": $h}}, spec: ($t.spec + {nodeName: "node-1"}),
     status: {containerStatuses: [{name: "sandboxd", containerID: $id, ready: true, image: $t.spec.containers[0].image, imageID: $iid}]}}]}' > "$state/pods.json"
  echo "${LAZY:-0}" > "$state/lazy"
  echo "${LOADING:-0}" > "$state/loading"
  echo "${BUSY:-0}" > "$state/busy"
  jq -n --arg c "$config" '{data: {"config.env": $c}}' > "$state/cm.json"
  [ "$3" = yes ] && touch "$state/arms"
  echo "${4:-$config_sum}" > "$state/loaded"
  cat > "$state/bin/kubectl" <<EOF
#!/usr/bin/env bash
state="$state"
config_sum="$config_sum"
repo="$repo"
EOF
  cat >> "$state/bin/kubectl" <<'EOF'
shift 2
echo "$*" >> "$state/calls"
case "$1 $2" in
  "get daemonset") cat "$state/ds.json" ;;
  "get controllerrevisions") cat "$state/revisions.json" ;;
  "get configmap") cat "$state/cm.json" ;;
  "get pods")
    # After a delete, the DaemonSet's replacement: pinned to the node by
    # affinity and still unscheduled, so without a nodeName.
    if [ -e "$state/order" ]; then
      jq -n '{items: [{metadata: {name: "sandboxd-y"}, spec: {affinity: {nodeAffinity: {requiredDuringSchedulingIgnoredDuringExecution: {nodeSelectorTerms: [{matchFields: [{key: "metadata.name", operator: "In", values: ["node-1"]}]}]}}}}}]}'
    else
      cat "$state/pods.json"
    fi ;;
  "get pod")
    if [ -e "$state/patched" ]; then
      jq -n --arg i "$repo:sha-new" '{status: {containerStatuses: [{name: "sandboxd", containerID: "containerd://new", ready: true, image: $i}]}}'
    else
      jq '.items[0]' "$state/pods.json"
    fi ;;
  "annotate pod")
    last="${!#}"
    if [[ "$last" == *=* ]]; then echo "${last#*=}" > "$state/marker"; else rm -f "$state/marker"; fi ;;
  "logs sandboxd-x")
    if [ -e "$state/arms" ] && [ -e "$state/marker" ] && [ ! -e "$state/patched" ]; then
      jq -cn --slurpfile m "$state/marker" --arg s "$config_sum" '{msg: "handover armed", nonce: $m[0].nonce, config_sha256: $s}'
    fi
    if [ -e "$state/patched" ]; then
      echo '{"msg":"sandbox re-attached","sandbox":"sbx-1"}'
    fi ;;
  "patch pod") echo "${!#}" > "$state/patch"; touch "$state/patched" ;;
  "delete pod") echo "$*" >> "$state/order" ;;
  "exec sandboxd-x")
    if [[ "$*" == *kill* ]]; then
      touch "$state/patched" "$state/killed"
      echo "$config_sum" > "$state/loaded"
    else
      lazy=$(cat "$state/lazy")
      echo "sandboxd_handover_blocked{reason=\"lazy_disks\"} $lazy"
      loading=$(cat "$state/loading")
      echo "sandboxd_handover_blocked{reason=\"memory_loading\"} $loading"
      [ "$lazy" = 0 ] && [ "$loading" -gt 0 ] && echo $((loading - 1)) > "$state/loading"
      echo 'sandboxd_handover_blocked{reason="memory_served"} 3'
      [ "$lazy" -gt 0 ] && echo $((lazy - 1)) > "$state/lazy"
      echo "sandboxd_config_info{sha256=\"$(cat "$state/loaded")\"} 1"
      busy=$(cat "$state/busy")
      echo "sandboxd_sandboxes{state=\"running\"} $busy"
      echo 'sandboxd_sandboxes{state="paused"} 0'
      [ "$busy" -gt 0 ] && echo $((busy - 1)) > "$state/busy"
    fi ;;
  *) ;;
esac
EOF
  printf '#!/bin/sh\n' > "$state/bin/sleep"
  chmod +x "$state/bin/kubectl" "$state/bin/sleep"
  PATH="$state/bin:$PATH" KUBECTL="$state/bin/kubectl" SANDBOXD_UPGRADE_SLEEP=1 SANDBOXD_UPGRADE_LAZY_WAIT_SECONDS=3 \
    SANDBOXD_UPGRADE_REPLACE_IDLE_SECONDS="${IDLE_WAIT:-0}" \
    bash "$script" tuist-sandboxes sandboxd > "$state/out" 2>&1 || { echo "script failed:"; cat "$state/out"; return 1; }
}

failures=0
check() {
  if eval "$2"; then
    echo "ok - $1"
  else
    echo "not ok - $1"
    sed 's/^/  /' "$state/out" "$state/calls" 2>/dev/null || true
    failures=$((failures + 1))
  fi
}

scenario sha-old sha-vmm yes
check "a daemon image change patches the Pod in place" \
  '[ -e "$state/patched" ] && ! grep -q "^delete" "$state/calls"'
check "the marker names the running container" \
  'grep -q "annotate pod sandboxd-x --overwrite sandboxes.tuist.dev/handover=.*\"container\":\"$old_id\"" "$state/calls"'
check "the patch sets the new image and revision" \
  'jq -e --arg i "$repo:sha-new" ".spec.containers[0].image == \$i and .metadata.labels.\"controller-revision-hash\" == \"new\"" "$state/patch" >/dev/null'
check "the marker is removed afterwards" '[ ! -e "$state/marker" ]'

scenario sha-old sha-vmm no
check "a daemon that never arms is replaced, not patched" \
  '[ ! -e "$state/patched" ] && grep -q "^delete pod sandboxd-x" "$state/calls" && [ ! -e "$state/marker" ]'

scenario sha-old sha-oldvmm yes
check "a vmm image change replaces the Pod" \
  '[ ! -e "$state/patched" ] && grep -q "^delete pod sandboxd-x" "$state/calls" && ! grep -q "^annotate" "$state/calls"'
check "a replacement still waiting to be scheduled on the node is found and awaited" \
  'grep -q "^wait --for=condition=Ready pod/sandboxd-y --timeout=600s" "$state/calls"'

scenario sha-new sha-vmm yes
check "a current Pod is left alone" \
  '! grep -qE "^(delete|patch|annotate)" "$state/calls"'

stale=$(printf old | sha256sum | cut -d' ' -f1)
scenario sha-new sha-vmm yes "$stale"
check "a config-only change restarts the daemon in place after it armed" \
  'grep -q "^annotate pod sandboxd-x --overwrite" "$state/calls" && [ -e "$state/patched" ] && ! grep -q "^delete" "$state/calls"'
check "a config-only restart patches in the image it runs by digest, not a SIGTERM" \
  '[ ! -e "$state/killed" ] && jq -e --arg i "$repo:sha-new@$digest" ".spec.containers[0].image == \$i" "$state/patch" >/dev/null'

POD_IMAGE=$repo:sha-new@$digest scenario sha-new sha-vmm yes "$stale"
check "the next config-only restart patches the digest away again" \
  '[ ! -e "$state/killed" ] && jq -e --arg i "$repo:sha-new" ".spec.containers[0].image == \$i" "$state/patch" >/dev/null'

POD_IMAGE=$repo:sha-new@$digest scenario sha-new sha-vmm yes
check "a Pod running its image by digest is current" \
  '! grep -qE "^(delete|patch|annotate)" "$state/calls"'

IMAGE_ID="" scenario sha-new sha-vmm yes "$stale"
check "without the running digest, a config-only change falls back to a SIGTERM" \
  '[ -e "$state/killed" ] && [ ! -e "$state/patch" ]'

scenario sha-new sha-vmm no "$stale"
check "a config-only change replaces a daemon that never arms" \
  '[ ! -e "$state/killed" ] && grep -q "^delete pod sandboxd-x" "$state/calls"'

LAZY=2 scenario sha-old sha-oldvmm yes
check "a replacement waits until no restore streams its disks" \
  'grep -q "2 sandboxes still receive their disks or memory" "$state/out" && [ "$(cat "$state/lazy")" = 0 ] &&
   [ "$(grep -n "still receive" "$state/out" | tail -1 | cut -d: -f1)" -lt "$(grep -n "^Replacing" "$state/out" | cut -d: -f1)" ]'

LAZY=1 LOADING=1 scenario sha-old sha-vmm yes
check "an in-place upgrade waits for memory still loading too, not for an old daemon's served memory" \
  'grep -q "2 sandboxes still receive their disks or memory" "$state/out" && grep -q "1 sandboxes still receive" "$state/out" &&
   [ "$(cat "$state/loading")" = 0 ] && [ -e "$state/patched" ]'

# The lazy-disk wait reads the metrics first, which drops BUSY to 2.
IDLE_WAIT=20 BUSY=3 scenario sha-old sha-oldvmm yes
check "a remote execution worker is replaced only once it holds no sandbox" \
  'grep -q "holds 2 sandboxes" "$state/out" && grep -q "holds 1 sandboxes" "$state/out" && [ "$(cat "$state/busy")" = 0 ] &&
   ! grep -q "did not drain" "$state/out" &&
   [ "$(grep -n "holds 1 sandboxes" "$state/out" | cut -d: -f1)" -lt "$(grep -n "^Replacing" "$state/out" | cut -d: -f1)" ]'

IDLE_WAIT=3 BUSY=9 scenario sha-old sha-oldvmm yes
check "a worker that does not drain in time is replaced anyway" \
  'grep -q "did not drain within 3s" "$state/out" && grep -q "^delete pod sandboxd-x" "$state/calls"'

BUSY=2 scenario sha-old sha-oldvmm yes
check "agent sandbox Pods are replaced without waiting for their sandboxes" \
  '! grep -q "holds" "$state/out" && [ "$(grep -c "^exec" "$state/calls")" = 1 ] && grep -q "^delete pod sandboxd-x" "$state/calls"'

IDLE_WAIT=20 BUSY=2 scenario sha-old sha-vmm yes
check "an in-place upgrade does not wait for the worker to drain" \
  '! grep -q "holds" "$state/out" && [ -e "$state/patched" ]'

[ "$failures" -eq 0 ] || { echo "$failures failures"; exit 1; }
