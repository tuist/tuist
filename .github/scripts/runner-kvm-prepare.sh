#!/usr/bin/env bash
# Prepare additive KVM prerequisites before Helm switches any Linux pools.
# Usage: runner-kvm-prepare.sh <rendered-json-array> <release> <namespace>
set -euo pipefail
render="${1:?rendered JSON array required}"
release="${2:?release required}"
namespace="${3:?namespace required}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fleets="$(jq -r '[.[] | select(.kind == "RunnerPool" and .spec.os == "linux" and .spec.nestedVirtualization == true) | .spec.fleetSelector] | unique[]' "$render")"
[[ -n "$fleets" ]] || exit 0

# A fresh cluster has no running pools to preserve; its normal install creates
# the provider and plugin, and node selectors protect the first runner Pods.
nodes="$(kubectl --request-timeout=30s get nodes -o json)"
if ! jq -e --arg fleets "$fleets" 'any(.items[]; .metadata.labels["node.cluster.x-k8s.io/pool"] as $pool | ($fleets | split("\n") | index($pool)) != null)' <<< "$nodes" >/dev/null; then
  echo 'No existing Linux runner hosts; normal installation will prepare them.'
  exit 0
fi

# Only the provider image and KVM plugin resources move ahead of the release.
# A failure leaves this additive preparation in place and ordinary pools intact.
provider="$(jq -er '[.[] | select(.kind == "Deployment" and .metadata.labels["app.kubernetes.io/component"] == "capi-scaleway-applesilicon")] | if length == 1 then .[0] else error("expected one CAPI provider") end' "$render")"
provider_name="$(jq -r '.metadata.name' <<< "$provider")"
provider_namespace="$(jq -r --arg ns "$namespace" '.metadata.namespace // $ns' <<< "$provider")"
provider_image="$(jq -er '.spec.template.spec.containers[] | select(.name == "manager") | .image' <<< "$provider")"
kubectl --request-timeout=30s -n "$provider_namespace" set image "deployment/$provider_name" "manager=$provider_image"
kubectl -n "$provider_namespace" rollout status "deployment/$provider_name" --timeout=10m

jq --arg release "$release" --arg ns "$namespace" '{apiVersion:"v1",kind:"List",items:[.[] |
  select(.metadata.labels["app.kubernetes.io/component"] == "kvm-device-plugin") |
  select(.kind == "ServiceAccount" or .kind == "ClusterRole" or .kind == "ClusterRoleBinding" or .kind == "DaemonSet") |
  .metadata.annotations["meta.helm.sh/release-name"] = $release |
  .metadata.annotations["meta.helm.sh/release-namespace"] = $ns |
  .metadata.labels["app.kubernetes.io/managed-by"] = "Helm"]}' "$render" > "$work/plugin.json"
jq -e '.items | length == 4' "$work/plugin.json" >/dev/null
kubectl --request-timeout=30s apply -f "$work/plugin.json"
plugin_name="$(jq -r '.items[] | select(.kind == "DaemonSet") | .metadata.name' "$work/plugin.json")"
plugin_namespace="$(jq -r '.items[] | select(.kind == "DaemonSet") | .metadata.namespace' "$work/plugin.json")"
kubectl -n "$plugin_namespace" rollout status "daemonset/$plugin_name" --timeout=10m

# Re-read through the wait: newly joined/rebooted hosts must carry current-boot
# preparation, and enough healthy device allocations for their whole Pod limit.
deadline=$((SECONDS + ${KVM_PREPARE_TIMEOUT_SECONDS:-600}))
while true; do
  kubectl --request-timeout=30s get nodes -o json > "$work/nodes.json"
  if jq -e --arg fleets "$fleets" -f "$(dirname "$0")/runner-kvm-ready.jq" "$work/nodes.json" >/dev/null; then
    echo 'Linux runner hosts have current-boot KVM preparation and allocations for every Pod slot.'
    break
  fi
  if (( SECONDS >= deadline )); then
    echo '::error::KVM preparation timed out; runner pools have not been switched.' >&2
    jq '[.items[] | {name:.metadata.name, kvm:.metadata.labels["tuist.dev/kata-kvm"], boot:.status.nodeInfo.bootID, proof:.metadata.annotations["tuist.dev/kata-kvm-config"], pods:.status.allocatable.pods, devices:.status.allocatable["devices.tuist.dev/kvm"]}]' "$work/nodes.json" >&2
    exit 1
  fi
  sleep 10
done
