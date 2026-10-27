#!/usr/bin/env bash
#MISE description="Check direct regional cache access on one Linux runner pool"
set -euo pipefail
ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
CHART="$ROOT/infra/helm/tuist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for ENVIRONMENT in staging canary production; do
  helm template tuist "$CHART" --namespace tuist \
    -f "$CHART/values-managed-common.yaml" \
    -f "$CHART/values-managed-${ENVIRONMENT}.yaml" \
    -f "$CHART/values-ci.yaml" --set runnersFleetLinux.cacheVolumes.enabled=true |
    yq -o json -I0 'select(.kind != null)' | jq -s . > "$WORK/render.json"
  jq -e '
    [.[] | select(.kind == "RunnerPool" and .spec.os == "linux")] as $pools |
    ($pools | length) > 0 and
    all($pools[]; .spec.fleetSelector == "runners-linux" and .metadata.labels["tuist.dev/network-cohort"] == null) and
    ([.[] | select(.kind == "Deployment") | .spec.template.spec.containers[].env[]? |
      select(.name == "TUIST_RUNNERS_LINUX_VRACK_POOLS" or .name == "TUIST_RUNNERS_LINUX_CACHE_RELAY")] | length) == 0 and
    ([.[] | select(.kind == "Deployment" and .spec.template.metadata.labels["app.kubernetes.io/name"] == "kura-runner-wan-relay")] | length) == 0 and
    any(.[]; .kind == "DaemonSet" and .spec.template.metadata.labels["app.kubernetes.io/component"] == "runner-cache-volumes" and
      .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "runners-linux")
  ' "$WORK/render.json" >/dev/null
  if [[ "$ENVIRONMENT" != staging ]]; then
    case "$ENVIRONMENT" in
      canary) VRACK=pn-2024092; REPLICAS=1 ;;
      production) VRACK=pn-2024093; REPLICAS=10 ;;
    esac
    jq -e --arg environment "$ENVIRONMENT" --arg vrack "$VRACK" --argjson replicas "$REPLICAS" '
      any(.[]; .kind == "OVHDedicatedMachineTemplate" and
        .spec.template.spec.adoptDisplayNamePrefix == ("tuist-runners-ovh-" + $environment) and
        .spec.template.spec.vRackID == $vrack) and
      any(.[]; .kind == "MachineDeployment" and
        .spec.template.metadata.labels["node.cluster.x-k8s.io/pool"] == "runners-linux" and .spec.replicas == $replicas)
    ' "$WORK/render.json" >/dev/null
  fi
  echo "$ENVIRONMENT: one Linux pool, direct cache access, no account-path mapping or relay."
done
