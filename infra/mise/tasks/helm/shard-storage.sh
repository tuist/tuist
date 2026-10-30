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
  pool=shard-storage
  region=null
  if [[ "$environment" == staging ]]; then
    pool=kura-ovh-gra-runners
    region='"ovh-gra-runners"'
  fi
  jq -e --arg size "$size" --arg pool "$pool" --argjson region "$region" '
    any(.[]; .kind == "StatefulSet" and .spec.replicas == 1 and
      .spec.template.metadata.labels["tuist.dev/region"] == $region and
      .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == $pool and
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
  if [[ "$environment" == staging ]]; then
    jq -e 'all(.[]; .kind != "Password" and .kind != "SecretStore")' "$WORK/$environment.json" >/dev/null
    continue
  fi
  case "$environment" in
    canary) server_namespace=tuist-canary vrack=pn-2024092 ;;
    production) server_namespace=tuist vrack=pn-2024093 ;;
  esac
  jq -e --arg environment "$environment" --arg ns "$server_namespace" --arg vrack "$vrack" '
    any(.[]; .kind == "StatefulSet" and
      .spec.template.spec.nodeSelector["tuist.dev/private-network"] == $vrack) and
    any(.[]; .kind == "Password" and .metadata.name == "shard-storage-seed") and
    ([.[] | select(.kind == "ExternalSecret" and .metadata.namespace == null)] |
      length == 1 and (.[0] | .spec.refreshPolicy == "CreatedOnce" and
        .spec.target.creationPolicy == "Orphan" and
        .spec.dataFrom[0].sourceRef.generatorRef.kind == "Password" and
        (.spec.target.template.data | keys) == ["access-key-id", "rpc-secret", "secret-access-key"])) and
    any(.[]; .kind == "Role" and .rules == [{"apiGroups": [""], "resources": ["secrets"], "resourceNames": ["shard-storage"], "verbs": ["get"]}]) and
    any(.[]; .kind == "SecretStore" and .metadata.namespace == $ns and
      .spec.provider.kubernetes.remoteNamespace == "kura") and
    any(.[]; .kind == "ExternalSecret" and .metadata.namespace == $ns and
      .spec.target.name == "shard-storage-targets" and
      (.spec.target.template.data["targets.json"] | fromjson | .["gra-" + $environment + "-v1"] |
        .site == "gra" and .enabled and .private_network_ready and .bucket == "shards" and
        .endpoint == "http://shard-storage.kura.svc.cluster.local:3900" and
        .access_key_id == "{{ .access_key_id }}" and .secret_access_key == "{{ .secret_access_key }}"))
  ' "$WORK/$environment.json" >/dev/null
done
echo 'All environments: singleton, placement, region accounting, controlled restart, matching disk reservation and three-day archives verified'
echo 'Canary and production: generated once-only credentials, private-network placement and a published server target verified'
if helm template shard-storage "$CHART" --namespace kura -f "$CHART/values-production.yaml" --set enabled=true --set externalSecrets.enabled=true --set externalSecrets.item=SHARD_STORAGE >/dev/null 2>&1; then
  echo 'Generated and 1Password credentials must not both define the store Secret' >&2
  exit 1
fi
MAIN_CHART="$ROOT/infra/helm/tuist"
for environment in canary production; do
  helm template tuist "$MAIN_CHART" --namespace tuist \
    -f "$MAIN_CHART/values-managed-common.yaml" \
    -f "$MAIN_CHART/values-managed-$environment.yaml" \
    -f "$MAIN_CHART/values-ci.yaml" |
    yq -o json -I0 'select(.kind != null)' | jq -s . > "$WORK/fleet-$environment.json"
  case "$environment" in
    canary) vrack=pn-2024092 ;;
    production) vrack=pn-2024093 ;;
  esac
  jq -e --arg environment "$environment" --arg vrack "$vrack" '
    [.[] | select(.kind == "OVHDedicatedMachineTemplate" and
      .spec.template.spec.adoptDisplayNamePrefix == ("tuist-shards-ovh-" + $environment))] as $templates |
    ($templates | length) == 1 and
    ($templates[0].spec.template.spec |
      .datacenter == "gra" and .vRackID == $vrack and .kataRuntime == null and
      .nodeTaints == [{"key": "tuist.dev/kura-cache", "value": "true", "effect": "NoSchedule"}]) and
    any(.[]; .kind == "MachineDeployment" and .metadata.name == $templates[0].metadata.name and
      .spec.replicas == 1 and .spec.strategy.type == "OnDelete" and
      .spec.template.metadata.labels["node.cluster.x-k8s.io/pool"] == "shard-storage") and
    any(.[]; .kind == "MachineDeployment" and .metadata.name == "tuist-tuist-ovh-fleet-runners-linux" and
      .spec.template.metadata.labels["node.cluster.x-k8s.io/shard-storage-site"] == "gra") and
    any(.[]; .kind == "Deployment" and (.metadata.name | endswith("-server")) and
      any(.spec.template.spec.containers[0].env[]; .name == "TUIST_SHARD_STORAGE_TARGETS" and
        .valueFrom.secretKeyRef == {"name": "shard-storage-targets", "key": "targets.json", "optional": true}))
  ' "$WORK/fleet-$environment.json" >/dev/null
done
echo 'Canary and production: one dedicated Gravelines storage host on the runner vRack, gra runners, and the server reading the published target'
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
