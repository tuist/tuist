#!/usr/bin/env bash
#MISE description="Sync management Flannel arguments from the Talos patch and verify private endpoints and pod connectivity"
#USAGE flag "--apply" help="Update Flannel instead of showing the desired arguments"
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
patch="$REPO_ROOT/infra/k8s/mgmt/talos/patches/60-private-flannel.yaml"
spec="${MGMT_TALOS_SPEC:-$REPO_ROOT/infra/k8s/mgmt/talos/hetzner.yaml}"
yq -e '.nodes | (tag == "!!seq" and length > 0 and all_c((.name | tag == "!!str") and (.privateIP | tag == "!!str")))' "$spec" >/dev/null
expected="$(yq -r '.nodes[] | .name + " " + .privateIP' "$spec")"
args="$(yq -o=json '.cluster.network.cni.flannel.extraArgs' "$patch" | jq -e '
  if type == "array" and length > 0 and all(.[]; type == "string")
  then ["--ip-masq", "--kube-subnet-mgr"] + . else error("missing Flannel arguments") end')"
echo "==> Flannel arguments: $(jq -c . <<<"$args")"
[[ "${1:-}" == --apply ]] || exit 0

# Talos's bootstrap inventory skips existing objects. Own only arguments,
# leaving its image, mounts, environment and security settings intact.
jq -n --argjson args "$args" '{
  apiVersion: "apps/v1", kind: "DaemonSet",
  metadata: {name: "kube-flannel", namespace: "kube-system"},
  spec: {template: {spec: {containers: [{name: "kube-flannel", args: $args}]}}}
}' | kubectl apply --server-side --field-manager=mgmt-flannel --force-conflicts -f -
kubectl -n kube-system rollout status daemonset/kube-flannel --timeout=5m

deadline=$((SECONDS + 180))
while true; do
  nodes="$(kubectl get nodes -o json)"
  valid=true
  while read -r node ip; do
    actual="$(jq -r --arg node "$node" '.items[] | select(.metadata.name == $node) | .metadata.annotations["flannel.alpha.coreos.com/public-ip"] // ""' <<<"$nodes")"
    if [[ "$actual" != "$ip" ]]; then
      echo "waiting for Flannel on $node: endpoint ${actual:-missing}, expected $ip"
      valid=false
    fi
  done <<<"$expected"
  $valid && break
  (( SECONDS < deadline )) || { echo "Flannel did not advertise every private IP" >&2; exit 1; }
  sleep 5
done
"$REPO_ROOT/infra/mise/tasks/mgmt/check-pod-network.sh"
