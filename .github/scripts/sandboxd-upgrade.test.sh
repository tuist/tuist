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

# template <daemon tag> <vmm tag>
template() {
  jq -cn --arg d "$repo:$1" --arg v "$repo:$2" '{
    metadata: {labels: {"app.kubernetes.io/name": "sandboxd"}},
    spec: {
      containers: [{name: "sandboxd", image: $d}, {name: "vmm", image: $v}],
      volumes: [{name: "config", configMap: {name: "sandboxd-config"}}]}}'
}

# scenario <pod's daemon tag> <pod's vmm tag> <arms: yes|no>; the
# DaemonSet always wants daemon sha-new and vmm sha-vmm.
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
  jq -n --argjson t "$have" --arg id "$old_id" --arg h "$hash" '{items: [
    {metadata: {name: "sandboxd-x", labels: {"controller-revision-hash": $h}}, spec: ($t.spec + {nodeName: "node-1"}),
     status: {containerStatuses: [{name: "sandboxd", containerID: $id, ready: true, image: $t.spec.containers[0].image}]}}]}' > "$state/pods.json"
  jq -n --arg c "$config" '{data: {"config.env": $c}}' > "$state/cm.json"
  [ "$3" = yes ] && touch "$state/arms"
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
    if [[ "$*" == *field-selector* ]]; then echo sandboxd-y; else cat "$state/pods.json"; fi ;;
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
  "exec sandboxd-x") echo 'sandboxd_handover_blocked{reason="lazy_disks"} 0' ;;
  *) ;;
esac
EOF
  printf '#!/bin/sh\n' > "$state/bin/sleep"
  chmod +x "$state/bin/kubectl" "$state/bin/sleep"
  PATH="$state/bin:$PATH" KUBECTL="$state/bin/kubectl" SANDBOXD_UPGRADE_SLEEP=1 SANDBOXD_UPGRADE_LAZY_WAIT_SECONDS=3 \
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

scenario sha-new sha-vmm yes
check "a current Pod is left alone" \
  '! grep -qE "^(delete|patch|annotate)" "$state/calls"'

[ "$failures" -eq 0 ] || { echo "$failures failures"; exit 1; }
