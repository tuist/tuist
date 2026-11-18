#!/usr/bin/env bash
#MISE description="Render isolated RustFS staging topology and security boundaries (no cluster writes)"
set -euo pipefail
ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
chart="$ROOT/infra/helm/shard-storage-rustfs"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
test -z "$(helm template rustfs "$chart")"
helm lint "$chart" -n rustfs-staging --set enabled=true
if helm template rustfs "$chart" -n kura --set enabled=true >/dev/null 2>&1; then
  echo 'FAIL: existing store namespace accepted' >&2; exit 1
fi
if helm template rustfs "$chart" -n rustfs-staging --set enabled=true --set ingress.enabled=true >/dev/null 2>&1; then
  echo 'FAIL: ingress accepted without explicit hostname and TLS Secret' >&2; exit 1
fi
helm template rustfs "$chart" -n rustfs-staging --set enabled=true \
  --set ingress.enabled=true --set ingress.host=shards.example.invalid --set ingress.tlsSecret=staging-tls \
  --set ingress.clusterIssuer=letsencrypt-cloudflare |
  yq -o json -I0 'select(.kind != null)' | jq -s . >"$work/render.json"
jq -e '
  any(.[]; .kind == "StatefulSet" and .spec.replicas == 4 and
    .spec.podManagementPolicy == "Parallel" and .spec.updateStrategy.type == "OnDelete" and
    .spec.persistentVolumeClaimRetentionPolicy == {whenDeleted:"Retain",whenScaled:"Retain"} and
    (.spec.volumeClaimTemplates | length) == 2 and
    all(.spec.volumeClaimTemplates[]; .spec.storageClassName == "hcloud-volumes") and
    .spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey == "kubernetes.io/hostname" and
    any(.spec.template.spec.containers[0].env[]; .name == "RUSTFS_STORAGE_CLASS_STANDARD" and .value == "EC:4") and
    .spec.template.spec.containers[0].readinessProbe.httpGet.path == "/health/ready") and
  all(.[] | select(.kind == "StatefulSet" or .kind == "Deployment");
    .spec.template.spec.automountServiceAccountToken == false and
    .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "general" and
    all(.spec.template.spec.containers[]; .securityContext.allowPrivilegeEscalation == false)) and
  any(.[]; .kind == "Deployment" and .spec.replicas == 2) and
  any(.[]; .kind == "PodDisruptionBudget" and .spec.minAvailable == 3) and
  all(.[] | select(.kind == "Service"); (.spec.type // "ClusterIP") == "ClusterIP") and
  ([.[] | select(.kind == "NetworkPolicy")] | length) == 2 and
  all(.[]; .kind != "Secret" and .kind != "ClusterRole" and .kind != "PersistentVolume") and
  any(.[]; .kind == "Ingress" and .spec.tls[0].secretName == "staging-tls" and
    .metadata.annotations["external-dns.alpha.kubernetes.io/cloudflare-proxied"] == "false" and
    .metadata.annotations["cert-manager.io/cluster-issuer"] == "letsencrypt-cloudflare" and
    .metadata.annotations["nginx.ingress.kubernetes.io/client-body-buffer-size"] == "1m" and
    .metadata.annotations["nginx.ingress.kubernetes.io/proxy-request-buffering"] == "off") and
  any(.[]; .kind == "ConfigMap" and
    (.data["default.conf"] | contains("proxy_set_header Host $http_host;") and
      contains("proxy_pass http://storage;") and contains("proxy_request_buffering off;") and
      contains("proxy_buffering off;") and contains("location / { return 404; }") and
      contains("access_log off;") and contains("error_log /dev/null;")))
' "$work/render.json" >/dev/null
if helm template rustfs "$chart" -n rustfs-staging --set enabled=true --set unsafeSharedDisks=true >/dev/null 2>&1; then
  echo 'FAIL: shared-disk bypass accepted for a multi-member store' >&2; exit 1
fi
helm template rustfs-ovh "$chart" -n rustfs-staging -f "$chart/values-staging-ovh.yaml" |
  yq -o json -I0 'select(.kind != null)' | jq -s . >"$work/ovh.json"
jq -e '
  any(.[]; .kind == "StatefulSet" and .spec.replicas == 1 and
    (.spec.volumeClaimTemplates | length) == 8 and
    all(.spec.volumeClaimTemplates[]; .spec.storageClassName == "scw-local-nvme") and
    (.spec.template.spec.containers[0].volumeMounts | map(.mountPath)) == ["/data0","/data1","/data2","/data3","/data4","/data5","/data6","/data7"] and
    any(.spec.template.spec.containers[0].env[]; .name == "RUSTFS_VOLUMES" and .value == "/data{0...7}") and
    any(.spec.template.spec.containers[0].env[]; .name == "RUSTFS_STORAGE_CLASS_STANDARD" and .value == "EC:4") and
    any(.spec.template.spec.containers[0].env[]; .name == "RUSTFS_UNSAFE_BYPASS_DISK_CHECK" and .value == "true")) and
  all(.[] | select(.kind == "StatefulSet" or .kind == "Deployment");
    .spec.template.spec.tolerations[0].key == "tuist.dev/kura-cache" and
    .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "kura-dedibox") and
  all(.[] | select(.kind == "PodDisruptionBudget"); .spec.minAvailable == 0) and
  any(.[]; .kind == "Ingress" and .spec.ingressClassName == "kura-eu-west" and
    .metadata.annotations["nginx.ingress.kubernetes.io/client-body-buffer-size"] == "1m")
' "$work/ovh.json" >/dev/null
helm template rustfs "$chart" -n rustfs-production -f "$chart/values-production-gra.yaml" |
  yq -o json -I0 'select(.kind != null)' | jq -s . >"$work/production.json"
jq -e '
  any(.[]; .kind == "StatefulSet" and .spec.replicas == 1 and
    (.spec.volumeClaimTemplates | length) == 1 and
    .spec.volumeClaimTemplates[0].spec.resources.requests.storage == "1000G" and
    any(.spec.template.spec.containers[0].env[]; .name == "RUSTFS_VOLUMES" and .value == "/data0") and
    all(.spec.template.spec.containers[0].env[]; .name != "RUSTFS_STORAGE_CLASS_STANDARD" and
      .name != "RUSTFS_UNSAFE_BYPASS_DISK_CHECK")) and
  all(.[]; .kind != "Secret") and
  ([.[] | select(.kind == "ExternalSecret" and .spec.refreshPolicy == "CreatedOnce" and
    .spec.target.creationPolicy == "Orphan") | .metadata.name] | sort) == ["rustfs-root","rustfs-service"] and
  any(.[]; .kind == "Role" and .rules == [{apiGroups:[""],resources:["secrets"],resourceNames:["rustfs-service"],verbs:["get"]}]) and
  any(.[]; .kind == "ExternalSecret" and .metadata.namespace == "tuist" and .spec.target.name == "rustfs-targets" and
    (.spec.target.template.data["targets.json"] | fromjson | .["rustfs-gra-production-v1"] |
      .access == "public" and .endpoint == "https://s3.tuist.dev" and .bucket == "shards" and .site == "gra")) and
  any(.[]; .kind == "CronJob" and .spec.jobTemplate.spec.template.metadata.labels == {app:"rustfs",component:"setup"}) and
  any(.[]; .kind == "Ingress" and .spec.rules[0].host == "s3.tuist.dev")
' "$work/production.json" >/dev/null
if helm template rustfs "$chart" -n rustfs-staging --set enabled=true --set target.id=x >/dev/null 2>&1; then
  echo 'FAIL: target published without generated credentials and a public host' >&2; exit 1
fi
echo 'PASS: production GRA store: one 1000G drive, generated credentials, in-cluster setup, public target'
echo 'PASS: single-member OVH performance variant: one member, eight drives, EC:4, kura-eu-west ingress'
echo 'PASS: disabled defaults, isolation, eight volumes, four hosts, EC:4, retained PVCs, streaming gateway and restricted services'
