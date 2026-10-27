#!/usr/bin/env bash
#MISE description="Check shared Linux runner capacity and the ordinary WAN cache path"
set -euo pipefail
ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
CHART="$ROOT/infra/helm/tuist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
render() {
  helm template tuist "$CHART" --namespace tuist \
    -f "$CHART/values-managed-common.yaml" \
    -f "$CHART/values-managed-${ENVIRONMENT}.yaml" \
    -f "$CHART/values-ci.yaml" "$@" |
    yq -o json -I0 'select(.kind != null)' | jq -s .
}
for ENVIRONMENT in staging canary production; do
  render --set kuraController.runnerCacheRelay.enabled=false > "$WORK/base.json"
  render --set kuraController.runnerCacheRelay.enabled=true > "$WORK/relay.json"
  jq -e -n --slurpfile base "$WORK/base.json" --slurpfile relay "$WORK/relay.json" '
    def pools: [.[] | select(.kind == "RunnerPool" and .spec.os == "linux")];
    def hardware: [.[] | select(.kind == "MachineDeployment" or .kind == "OVHDedicatedMachineTemplate")];
    ($relay[0] | pools) as $pools |
    ($pools | length) > 0 and ($pools == ($base[0] | pools)) and
    all($pools[]; .spec.fleetSelector == "runners-linux" and .metadata.labels["tuist.dev/network-cohort"] == null) and
    (($base[0] | hardware) == ($relay[0] | hardware)) and
    ([ $relay[0][] | select(.kind == "Deployment") | .spec.template.spec.containers[].env[]? |
       select(.name == "TUIST_RUNNERS_LINUX_VRACK_POOLS") ] | length) == 0 and
    any($relay[0][]; .kind == "Deployment" and
       any(.spec.template.spec.containers[].env[]?; .name == "TUIST_RUNNERS_LINUX_CACHE_RELAY" and .value == "true")) and
    ([ $relay[0][] | select(.kind == "Deployment" and .spec.template.metadata.labels["app.kubernetes.io/name"] == "kura-runner-wan-relay") ] | length) == 1 and
    all($relay[0][] | select(.kind == "Deployment" and .spec.template.metadata.labels["app.kubernetes.io/name"] == "kura-runner-wan-relay");
      .spec.replicas == 2 and .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "general" and
      .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0] ==
        {"key":"tuist.dev/private-network", "operator":"DoesNotExist"} and
      .spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey == "kubernetes.io/hostname" and
      .spec.template.spec.containers[0].command == ["/runner-cache-relay"]) and
    all($relay[0][] | select(.kind == "DaemonSet" and .spec.template.metadata.labels["app.kubernetes.io/component"] == "runner-cache-volumes");
      .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "runners-linux")
  ' >/dev/null
  echo "$ENVIRONMENT: one runner cohort; relay preserves pools/hardware, runs outside vRack, and has two separate hosts."
done
yq -e '.kuraController.runnerCacheRelay.enabled == false' "$CHART/values.yaml" >/dev/null
# Only canary switches ordinary traffic during initial qualification.
for ENVIRONMENT in staging production; do
  render > "$WORK/default.json"
  jq -e '[.[] | select(.kind == "Deployment" and .spec.template.metadata.labels["app.kubernetes.io/name"] == "kura-runner-wan-relay")] | length == 0' "$WORK/default.json" >/dev/null
done
ENVIRONMENT=canary
render > "$WORK/default.json"
jq -e '[.[] | select(.kind == "Deployment" and .spec.template.metadata.labels["app.kubernetes.io/name"] == "kura-runner-wan-relay")] | length == 1' "$WORK/default.json" >/dev/null
