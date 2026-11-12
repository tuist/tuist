#!/usr/bin/env bash
set -euo pipefail
chart="$(dirname "${BASH_SOURCE[0]}")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
helm lint "$chart" --namespace observability
helm template greptimedb "$chart" --namespace observability > "$tmp/rendered.yaml"
yq ea -o=json -I=0 '.' "$tmp/rendered.yaml" | jq -s 'map(select(. != null))' > "$tmp/resources.json"
jq -e '
  length == 5 and
  all(.[]; .kind != "Secret" and .kind != "Ingress" and .kind != "ClusterRole") and
  any(.[]; .kind == "Service" and .spec.type == "ClusterIP" and (.spec.ports | length) == 1) and
  any(.[]; .kind == "StatefulSet" and .spec.replicas == 1 and
    .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "general" and
    .spec.template.spec.automountServiceAccountToken == false and
    .spec.persistentVolumeClaimRetentionPolicy == {whenDeleted:"Retain",whenScaled:"Retain"} and
    .spec.volumeClaimTemplates[0].spec.resources.requests.storage == "10Gi" and
    .spec.template.spec.containers[0].image == "docker.io/greptime/greptimedb:v1.3.0" and
    .spec.template.spec.containers[0].readinessProbe.httpGet.path == "/health" and
    .spec.template.spec.containers[0].envFrom[0].secretRef.name == "greptimedb-credentials") and
  any(.[]; .kind == "ConfigMap" and
    (.data["config.toml"] | contains("provider = \"raft_engine\"", "root = \"greptimedb/\"", "type = \"S3\"", "user_provider = \"static_user_provider:file:"))) and
  any(.[]; .kind == "ExternalSecret" and
    ([.spec.data[].remoteRef.key] | sort) == ["PULSE_S3_CREDENTIALS/access_key_id","PULSE_S3_CREDENTIALS/secret_access_key"]) and
  any(.[]; .kind == "NetworkPolicy" and .spec.ingress[0].from == [{podSelector:{}}])
' "$tmp/resources.json" > /dev/null
for setting in storage.prefix=tenants/ storage.bucket=tuist-pulso-production; do
  if helm template greptimedb "$chart" -n observability --set "$setting" > "$tmp/refused.log" 2>&1; then
    echo "FAIL: unsafe storage setting accepted: $setting" >&2
    exit 1
  fi
  grep -Fq "selected environment's isolated greptimedb/ prefix" "$tmp/refused.log"
done
for environment in staging canary production; do
  ns="tuist-$environment"
  if [[ "$environment" == production ]]; then ns=tuist; fi
  helm template greptimedb "$chart" -n observability \
    --set "environment=$environment,storage.bucket=tuist-pulso-$environment,dashboard.enabled=true" > "$tmp/scoped.yaml"
  yq ea -o=json -I=0 '.' "$tmp/scoped.yaml" | jq -s --arg ns "$ns" '
    map(select(. != null)) |
    length == 6 and
    any(.[]; .kind == "ExternalSecret" and .metadata.name == "greptimedb-dashboard-auth" and
      .spec.data[0].remoteRef.key == "PULSE_TOKEN/password" and
      (.spec.target.template.data.passwd | contains("dashboard:ro=", "tuist:wo="))) and
    any(.[]; .kind == "StatefulSet" and
      .spec.template.spec.initContainers[0].name == "combine-auth" and
      any(.spec.template.spec.volumes[]; .name == "auth-inputs" and (.projected.sources | length) == 2)) and
    any(.[]; .kind == "NetworkPolicy" and
      .spec.ingress[1].from == [{namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":$ns}},
        podSelector:{matchLabels:{"app.kubernetes.io/component":"server"}}}] and
      .spec.ingress[2].from == [{namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":$ns}},
        podSelector:{matchLabels:{"app.kubernetes.io/name":"tuist","app.kubernetes.io/instance":"tuist","app.kubernetes.io/component":"pdc-agent"}}}] and
      .spec.ingress[2].ports == [{port:4000,protocol:"TCP"}])
  ' | grep -qx true
done
if helm template greptimedb "$chart" -n observability --set environment=other > /dev/null 2>&1; then exit 1; fi
if helm template greptimedb "$chart" -n default > /dev/null 2>&1; then exit 1; fi
helm template greptimedb "$chart" -n observability -f "$chart/values-production.yaml" > "$tmp/prod.yaml"
yq -o=json 'select(.kind == "StatefulSet").spec.template.spec.containers[0].resources' "$tmp/prod.yaml" |
  jq -e '. == {requests:{cpu:"1",memory:"2Gi"},limits:{memory:"4Gi"}}' >/dev/null
echo 'PASS: per-environment private backend, scoped auth, isolated S3 prefix and retained WAL volume'
