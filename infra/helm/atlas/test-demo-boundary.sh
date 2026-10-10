#!/usr/bin/env bash
set -euo pipefail
chart="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

helm template atlas-demo "$chart" -f "$chart/values-demo.yaml" --namespace atlas-demo > "$work/demo.yaml"
yq -o=json -I=0 '.' "$work/demo.yaml" | jq -s '.' > "$work/demo.json"
jq -e '
  (map(select(.kind == "Deployment"))[0].spec.template.spec) as $pod |
  ($pod.automountServiceAccountToken == false) and
  ($pod.enableServiceLinks == false) and
  ($pod.volumes == null) and
  ($pod.containers[0].envFrom[0].secretRef.name == "atlas-demo-app") and
  ($pod.initContainers[0].envFrom[0].secretRef.name == "atlas-demo-migrator") and
  ($pod.initContainers[0].command[2] | contains("Atlas.Release.seed_demo()")) and
  ([$pod.containers[0].env[] | select(.name == "ATLAS_DEMO_MODE") | .value] == ["true"]) and
  (map(select(.kind == "NetworkPolicy"))[0].spec.egress | length == 2) and
  (map(select(.kind == "NetworkPolicy"))[0].spec.egress[1].ports == [{"protocol":"TCP","port":5432}]) and
  (map(select(.kind == "NetworkPolicy"))[0].spec.egress[1].to[0].namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "atlas-demo") and
  (map(select(.kind == "Ingress"))[0].spec.rules[0].host == "demo.atlas.tuist.dev") and
  (map(select(.kind == "Cluster" or .kind == "ExternalSecret" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding")) | length == 0)
' "$work/demo.json" > /dev/null

for setting in tuistServer.enabled postgres.enabled clickhouse.enabled vector.enabled externalSecrets.enabled agentSandboxes.enabled; do
  if helm template atlas-demo "$chart" -f "$chart/values-demo.yaml" --set "$setting=true" > /dev/null 2>&1; then
    echo "Demo unexpectedly accepted $setting" >&2
    exit 1
  fi
done
if helm template atlas-demo "$chart" -f "$chart/values-demo.yaml" --set migrationJob.appSecretName=atlas-demo-app > /dev/null 2>&1; then
  echo "Demo unexpectedly accepted shared write credentials" >&2
  exit 1
fi
for value in true TRUE 1 yes YES; do
  if helm template standalone "$chart" --set-string "env.ATLAS_DEMO_MODE=$value" > /dev/null 2>&1; then
    echo "Non-demo chart unexpectedly accepted ATLAS_DEMO_MODE=$value" >&2
    exit 1
  fi
done
if helm template atlas-demo "$chart" -f "$chart/values-demo.yaml" --set-string env.ATLAS_DEMO_MODE=false > /dev/null 2>&1; then
  echo "Demo chart unexpectedly accepted a disabled runtime guard" >&2
  exit 1
fi
helm template managed "$chart" -f "$chart/values-managed-production.yaml" > "$work/managed.yaml"
helm template standalone "$chart" > "$work/standalone.yaml"
for manifest in standalone managed; do
  for container in containers initContainers; do
    yq -e "select(.kind == \"Deployment\") | .spec.template.spec.$container[].env[] | select(.name == \"ATLAS_DEMO_MODE\") | .value == \"false\"" "$work/$manifest.yaml" > /dev/null
  done
done
if yq 'select(.kind == "NetworkPolicy") | .metadata.name' "$work/standalone.yaml" | grep -q .; then
  echo "Demo network policy leaked into standalone deployment" >&2
  exit 1
fi
printf '%s\n' 'Atlas demo boundary passed: production auth enforced, separate credentials, fictional seeds, no connectors, restricted egress.'
