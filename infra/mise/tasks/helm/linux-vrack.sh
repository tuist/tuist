#!/usr/bin/env bash
#MISE description="Check account-gated Linux vRack pools are isolated without changing ordinary capacity"
set -euo pipefail
ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
CHART="$ROOT/infra/helm/tuist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

render() {
  helm template tuist "$CHART" --namespace tuist \
    -f "$CHART/values-managed-common.yaml" \
    -f "$CHART/values-managed-production.yaml" \
    -f "$CHART/values-ci.yaml" "$@" |
    yq -o json -I0 'select(.kind != null)' | jq -s .
}
render > "$WORK/base.json"
render -f "$ROOT/infra/kura-controller/production-linux-runner-vrack.values.yaml" > "$WORK/vrack.json"

# Keep the workload and cache-agent checks separate so failures are diagnosable.
jq -e -n --slurpfile base "$WORK/base.json" --slurpfile vrack "$WORK/vrack.json" '
  def pools: [.[] | select(.kind == "RunnerPool" and .spec.os == "linux")];
  def hardware: [.[] | select(.kind == "MachineDeployment" or .kind == "OVHDedicatedMachineTemplate")];
  ($base[0] | pools) as $ordinary |
  ($vrack[0] | pools) as $all |
  ($all | map(select(.metadata.labels["tuist.dev/network-cohort"] == "vrack"))) as $isolated |
  ($all | map(select(.metadata.labels["tuist.dev/network-cohort"] != "vrack"))) as $unchanged |
  ([ $vrack[0][] | select(.kind == "Deployment") | .spec.template.spec.containers[].env[]? |
     select(.name == "TUIST_RUNNERS_LINUX_VRACK_POOLS") | .value | fromjson ][0]) as $mapping |
  ($ordinary | length) > 0 and ($isolated | length) > 0 and
  ($unchanged == $ordinary) and
  (($base[0] | hardware) == ($vrack[0] | hardware)) and
  (($mapping | length) == ($isolated | length)) and
  all($isolated[];
    . as $pool |
    .spec.fleetSelector == "runners-linux-vrack" and
    .spec.replicas == 0 and .spec.autoscaling.minWarmPoolFloor == 0 and
    ([ $ordinary[] | select(.metadata.name as $name | $mapping[$name] == $pool.metadata.name) |
       select(.spec.fleetSelector != $pool.spec.fleetSelector and
              .spec.podCPUMilli == $pool.spec.podCPUMilli and
              .spec.podMemoryMB == $pool.spec.podMemoryMB and
              .spec.image == $pool.spec.image and
              .spec.runtimeClass == $pool.spec.runtimeClass) ] | length) == 1
  )
' >/dev/null
jq -e '
  [.[] | select(.kind == "DaemonSet" and .spec.template.metadata.labels["app.kubernetes.io/component"] == "runner-cache-volumes")][0] |
  .spec.template.spec as $pod |
  $pod.nodeSelector["kubernetes.io/os"] == "linux" and
  any($pod.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions[];
    .key == "node.cluster.x-k8s.io/pool" and .operator == "In" and
    (.values | sort) == ["runners-linux", "runners-linux-vrack"])
' "$WORK/vrack.json" >/dev/null
if render --set runnersFleetLinux.vrack.enabled=true --set runnersFleetLinux.vrack.nodePool=runners-linux > "$WORK/invalid.json" 2> "$WORK/error"; then
  echo 'ERROR: overlapping ordinary/vRack selectors were accepted' >&2
  exit 1
fi
grep -Fq 'vRack runner node pool must differ' "$WORK/error"
echo 'vRack pools are disjoint, ordinary pools and hardware are unchanged, and the cache-volume agent covers both cohorts.'
