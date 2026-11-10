#!/usr/bin/env bash
# Offline safety checks; no Kubernetes or object-store calls.
set -euo pipefail
chart="$(dirname "${BASH_SOURCE[0]}")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for environment in staging canary production; do
  case "$environment" in
    staging) metadata_instances=1; backend_instances=1 ;;
    canary) metadata_instances=2; backend_instances=1 ;;
    production) metadata_instances=2; backend_instances=2 ;;
  esac
  helm lint "$chart" -f "$chart/values-$environment.yaml"
  helm template openobserve "$chart" -n observability \
    -f "$chart/values-$environment.yaml" > "$tmp/rendered.yaml"
  yq ea -o=json -I=0 '.' "$tmp/rendered.yaml" | jq -s 'map(select(. != null))' > "$tmp/resources.json"
  jq -e --arg bucket "tuist-pulso-$environment" --argjson metadata "$metadata_instances" \
    --argjson replicas "$backend_instances" '
  all(.[]; .kind != "Ingress" and .kind != "ClusterRole" and .kind != "ClusterRoleBinding") and
  all(.[] | select(.kind == "Service"); (.spec.type // "ClusterIP") == "ClusterIP") and
  any(.[]; .kind == "Deployment" and .metadata.name == "openobserve-router" and .spec.replicas == $replicas) and
  any(.[]; .kind == "StatefulSet" and .metadata.name == "openobserve-ingester" and .spec.replicas == $replicas) and
  all(.[] | select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.replicas > 0);
    .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "general") and
  all(.[] | select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] |
    select(.name | startswith("openobserve-"));
    .image == "o2cr.ai/openobserve/openobserve:v1.1.2" and
    any(.env[]; .name == "ZO_META_POSTGRES_DSN" and
      .valueFrom.secretKeyRef == {name:"openobserve-metadata-app",key:"uri"}) and
    any(.env[]; .name == "ZO_ROOT_USER_PASSWORD" and
      .valueFrom.secretKeyRef == {name:"openobserve-auth",key:"root-password"}) and
    any(.env[]; .name == "ZO_INTERNAL_GRPC_TOKEN" and
      .valueFrom.secretKeyRef == {name:"openobserve-auth",key:"internal-token"}) and
    any(.envFrom[]; .secretRef.name == "openobserve-credentials")) and
  any(.[]; .kind == "Cluster" and .metadata.name == "openobserve-metadata" and
    .spec.instances == $metadata and .spec.enableSuperuserAccess == false and
    .spec.bootstrap.initdb.owner == "openobserve" and
    .spec.affinity.nodeSelector["node.cluster.x-k8s.io/pool"] == "general") and
  any(.[]; .kind == "ExternalSecret" and .metadata.name == "openobserve-credentials" and
    .spec.target.template.data.ZO_S3_BUCKET_NAME == $bucket and
    .spec.target.template.data.ZO_S3_BUCKET_PREFIX == "openobserve/" and
    .spec.target.template.data.ZO_S3_SERVER_URL == "https://t3.storage.dev" and
    ([.spec.data[].remoteRef.key] | sort) ==
      ["PULSE_S3_CREDENTIALS/access_key_id", "PULSE_S3_CREDENTIALS/secret_access_key"]) and
  all(.[] | select(.kind == "ConfigMap") | .data;
    (.ZO_COMPACT_DATA_RETENTION_DAYS // "0") == "0") and
  any(.[]; .kind == "NetworkPolicy" and .metadata.name == "openobserve-private")
  ' "$tmp/resources.json" > /dev/null
  echo "PASS: $environment private OSS topology, independent auth and isolated S3 prefix"
done

if helm template openobserve "$chart" -n observability > "$tmp/missing.log" 2>&1; then
  echo "FAIL: missing storage configuration accepted" >&2
  exit 1
fi
grep -Fq 'storage.bucket is required' "$tmp/missing.log"
if helm template openobserve "$chart" -n observability -f "$chart/values-production.yaml" \
  --set storage.prefix=tenants/ > "$tmp/prefix.log" 2>&1; then
  echo "FAIL: Pulse namespace accepted" >&2
  exit 1
fi
grep -Fq 'storage.prefix must be openobserve/' "$tmp/prefix.log"
echo 'PASS: private OSS deployment, metadata credentials, S3 isolation and fail-closed storage guards'
