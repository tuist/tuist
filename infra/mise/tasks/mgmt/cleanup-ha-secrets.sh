#!/usr/bin/env bash
#MISE description="Check and optionally delete the unused management Tailscale rollback Secrets and the abandoned temporary-node state"
#USAGE flag "--apply" help="Delete only the verified obsolete Secret names"
set -euo pipefail

apply=false
case "${1:-}" in
  "") ;;
  --apply) apply=true ;;
  *) echo "usage: $0 [--apply]" >&2; exit 1 ;;
esac
fail() { echo "error: $*" >&2; exit 1; }

nodes=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o json)
count=$(jq '.items | length' <<<"$nodes")
(( count >= 3 )) || fail "expected at least three control-plane nodes"
jq -e 'all(.items[]; any(.status.conditions[]; .type == "Ready" and .status == "True"))' <<<"$nodes" >/dev/null || fail "a control-plane node is not Ready"

kubectl -n mgmt-tailscale get daemonset tailscale -o json | jq -e --argjson count "$count" '
  .status.observedGeneration == .metadata.generation and
  .status.desiredNumberScheduled == $count and
  .status.updatedNumberScheduled == $count and
  .status.numberReady == $count and .status.numberAvailable == $count
' >/dev/null || fail "the per-node Tailscale DaemonSet is not fully rolled out"
kubectl -n mgmt-tailscale get secret tailscale-oauth -o name >/dev/null
while read -r node; do
  kubectl -n mgmt-tailscale get secret "tailscale-state-$node" -o name >/dev/null
done < <(jq -r '.items[].metadata.name' <<<"$nodes")

# Look at workload specifications and RBAC, never Secret data. References in
# retained old Jobs also block cleanup; investigate them instead of guessing.
resources=pods,deployments,daemonsets,statefulsets,replicasets,jobs,cronjobs,serviceaccounts,roles,rolebindings,externalsecrets
legacy=$(kubectl -n mgmt-system get "$resources" -o json)
jq -e '[.items[] | select(any(.. | strings; contains("tailscale")))] | length == 0' <<<"$legacy" >/dev/null || fail "mgmt-system still contains a Tailscale workload or reference"

ghost=talos-sif-xr2
# Check all Nodes, not only control-plane Nodes, before removing dynamic state.
kubectl get nodes -o json | jq -e --arg ghost "$ghost" 'all(.items[]; .metadata.name != $ghost)' >/dev/null || fail "$ghost still exists as a Kubernetes node"
kubectl -n mgmt-tailscale get "$resources" -o json | jq -e --arg ghost "$ghost" '
  [.items[] | select(any(.. | strings; contains($ghost)))] | length == 0
' >/dev/null || fail "a workload still references $ghost"

remove() {
  local namespace=$1 name=$2
  if $apply; then
    kubectl -n "$namespace" delete secret "$name" --ignore-not-found
  else
    echo "would delete Secret $namespace/$name (if present)"
  fi
}
remove mgmt-system tailscale-oauth
remove mgmt-system tailscale-state
remove mgmt-tailscale "tailscale-state-$ghost"
