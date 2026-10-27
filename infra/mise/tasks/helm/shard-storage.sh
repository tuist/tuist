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
