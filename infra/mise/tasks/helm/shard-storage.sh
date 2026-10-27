#!/usr/bin/env bash
#MISE description="Validate isolated runner-local shard storage and disk reservation"
set -euo pipefail
ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
CHART="$ROOT/infra/helm/shard-storage"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
helm lint "$CHART" --namespace kura --set enabled=true --set externalSecrets.item=SHARD_STORAGE
test -z "$(helm template shard-storage "$CHART")"
if helm template shard-storage "$CHART" --namespace wrong --set enabled=true --set externalSecrets.item=SHARD_STORAGE >/dev/null 2>&1; then
  echo 'Installing outside the capacity-accounted namespace must fail' >&2
  exit 1
fi
helm template shard-storage "$CHART" --namespace kura --set enabled=true --set externalSecrets.item=SHARD_STORAGE |
  yq -o json -I0 'select(.kind != null)' | jq -s . > "$WORK/render.json"
jq -e '
  any(.[]; .kind == "StatefulSet" and .spec.replicas == 1 and
    .spec.template.metadata.labels["tuist.dev/region"] == "eu-west" and
    .spec.template.spec.automountServiceAccountToken == false and
    any(.spec.template.spec.tolerations[]; .key == "tuist.dev/kura-cache" and .value == "true" and .effect == "NoSchedule") and
    .spec.template.spec.containers[0].resources.requests["ephemeral-storage"] == "200Gi" and
    .spec.template.spec.containers[0].resources.limits["ephemeral-storage"] == null and
    .spec.volumeClaimTemplates[0].spec.resources.requests.storage == "200Gi" and
    .spec.volumeClaimTemplates[0].spec.storageClassName == "scw-local-nvme") and
  all(.[] | select(.kind == "Service"); .spec.type == "ClusterIP" and [.spec.ports[].port] == [3900]) and
  any(.[]; .kind == "NetworkPolicy" and [.spec.ingress[].ports[].port] == [3900] and .spec.egress == []) and
  any(.[]; .kind == "CronJob" and .spec.concurrencyPolicy == "Forbid") and
  any(.[]; .kind == "ConfigMap" and .data["lifecycle.json"] != null and
    (.data["lifecycle.json"] | fromjson | .Rules[0].Expiration.Days == 31))
' "$WORK/render.json" >/dev/null
echo 'Shard storage: disabled default, quota reservation, private S3 service and lifecycle verified'
for environment in staging canary production; do
  helm lint "$CHART" --namespace kura -f "$CHART/values-$environment.yaml" --set enabled=true --set externalSecrets.item=SHARD_STORAGE
  helm template shard-storage "$CHART" --namespace kura -f "$CHART/values-$environment.yaml" --set enabled=true --set externalSecrets.item=SHARD_STORAGE |
    yq -o json -I0 'select(.kind != null)' | jq -s . > "$WORK/$environment.json"
  size=200Gi
  if [[ "$environment" == production ]]; then size=3Ti; fi
  jq -e --arg size "$size" '
    any(.[]; .kind == "StatefulSet" and .spec.replicas == 1 and
      .spec.updateStrategy.type == "OnDelete" and
      (.spec.template.spec.containers[0].args | index("--single-node")) != null and
      .spec.template.spec.containers[0].resources.requests["ephemeral-storage"] == $size and
      .spec.volumeClaimTemplates[0].spec.resources.requests.storage == $size) and
    all(.[]; .kind != "PodDisruptionBudget") and
    all(.[] | select(.kind == "Service"); [.spec.ports[].port] == [3900]) and
    any(.[]; .kind == "ConfigMap" and .data["lifecycle.json"] != null and
      (.data["lifecycle.json"] | fromjson | .Rules[0].Expiration.Days == 3 and
        .Rules[0].AbortIncompleteMultipartUpload.DaysAfterInitiation == 1))
  ' "$WORK/$environment.json" >/dev/null
done
echo 'All environments: singleton, controlled restart, matching disk reservation and three-day archives verified'
helm lint "$CHART" --namespace kura -f "$CHART/values-production.yaml" -f "$CHART/values-replicated.yaml" --set enabled=true --set externalSecrets.item=SHARD_STORAGE
helm template shard-storage "$CHART" --namespace kura -f "$CHART/values-production.yaml" -f "$CHART/values-replicated.yaml" --set enabled=true --set externalSecrets.item=SHARD_STORAGE |
  yq -o json -I0 'select(.kind != null)' | jq -s . > "$WORK/replicated.json"
jq -e '
  any(.[]; .kind == "StatefulSet" and .spec.replicas == 3 and
    .spec.serviceName == "shard-storage-peers" and
    .spec.podManagementPolicy == "Parallel" and .spec.updateStrategy.type == "OnDelete" and
    .spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey == "kubernetes.io/hostname" and
    .spec.template.spec.containers[0].args == ["server"] and
    .spec.template.spec.containers[0].resources.requests["ephemeral-storage"] == "3Ti" and
    .spec.volumeClaimTemplates[0].spec.resources.requests.storage == "3Ti" and
    .spec.template.spec.automountServiceAccountToken == false) and
  any(.[]; .kind == "PodDisruptionBudget" and .spec.minAvailable == 2) and
  any(.[]; .kind == "Service" and .metadata.name == "shard-storage-peers" and
    .spec.clusterIP == "None" and .spec.publishNotReadyAddresses and [.spec.ports[].port] == [3901]) and
  any(.[]; .kind == "Service" and .metadata.name == "shard-storage" and [.spec.ports[].port] == [3900]) and
  any(.[]; .kind == "NetworkPolicy" and [.spec.ingress[].ports[].port] == [3900,3901] and
    [.spec.egress[].ports[].port] == [3901,53,53] and
    .spec.egress[0].to[0].podSelector.matchLabels["app.kubernetes.io/instance"] == "shard-storage") and
  any(.[]; .kind == "ConfigMap" and .data["garage.toml"] != null and
    (.data["garage.toml"] | contains("replication_factor = 3") and contains("consistency_mode = \"consistent\"") and
      contains("data_fsync = true") and contains("metadata_fsync = true")))
' "$WORK/replicated.json" >/dev/null
for replicas in 0 2 4 1.5; do
  if helm template shard-storage "$CHART" --namespace kura --set enabled=true --set externalSecrets.item=SHARD_STORAGE --set replicas="$replicas" >/dev/null 2>&1; then
    echo "Unsafe replica count $replicas accepted" >&2
    exit 1
  fi
done
echo 'Optional replication: three hosts, quorum budget, manual rollout, private peer network and durable writes verified'
for field in expirationDays abortMultipartDays; do
  for days in 0 -1 1.5; do
    if helm template shard-storage "$CHART" --namespace kura --set enabled=true --set externalSecrets.item=SHARD_STORAGE --set "lifecycle.$field=$days" >/dev/null 2>&1; then
      echo "Invalid lifecycle $field=$days accepted" >&2
      exit 1
    fi
  done
done
echo 'Lifecycle: nonpositive and fractional retention rejected'
