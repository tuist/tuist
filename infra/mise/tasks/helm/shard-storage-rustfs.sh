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
    .metadata.annotations["nginx.ingress.kubernetes.io/proxy-request-buffering"] == "off") and
  any(.[]; .kind == "ConfigMap" and
    (.data["default.conf"] | contains("proxy_set_header Host $http_host;") and
      contains("proxy_pass http://storage;") and contains("proxy_request_buffering off;") and
      contains("proxy_buffering off;") and contains("location / { return 404; }") and
      contains("access_log off;") and contains("error_log /dev/null;")))
' "$work/render.json" >/dev/null
echo 'PASS: disabled defaults, isolation, eight volumes, four hosts, EC:4, retained PVCs, streaming gateway and restricted services'
