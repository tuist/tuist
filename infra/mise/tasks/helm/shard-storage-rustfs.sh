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
      contains("access_log /dev/stdout rustfs_access;") and contains("error_log /dev/null;")))
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
    (.spec.template.spec.containers[0].volumeMounts | map(.mountPath) | map(select(startswith("/data")))) == ["/data0","/data1","/data2","/data3","/data4","/data5","/data6","/data7"] and
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
    .spec.target.creationPolicy == "Orphan") | .metadata.name] | sort) == ["rustfs-docker-mirror-service","rustfs-root","rustfs-service"] and
  any(.[]; .kind == "Role" and .rules == [{apiGroups:[""],resources:["secrets"],resourceNames:["rustfs-service","rustfs-docker-mirror-service"],verbs:["get"]}]) and
  any(.[]; .kind == "ExternalSecret" and .metadata.namespace == "tuist" and .spec.target.name == "rustfs-targets" and
    (.spec.target.template.data["targets.json"] | fromjson | .["rustfs-gra-production-v1"] |
      .access == "public" and .endpoint == "https://s3.tuist.dev" and .bucket == "shards" and .site == "gra")) and
  any(.[]; .kind == "CronJob" and .spec.jobTemplate.spec.template.metadata.labels == {app:"rustfs",component:"setup"}) and
  any(.[]; .kind == "Ingress" and .spec.rules[0].host == "s3.tuist.dev") and
  any(.[]; .kind == "StatefulSet" and
    ([.spec.template.spec.containers[0].env[] | select(.name | startswith("RUSTFS_OBS_")) | {(.name): .value}] | add) == {
      RUSTFS_OBS_METRIC_ENDPOINT: "http://k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4318/v1/metrics",
      RUSTFS_OBS_SERVICE_NAME: "rustfs",
      RUSTFS_OBS_TRACES_EXPORT_ENABLED: "false",
      RUSTFS_OBS_LOGS_EXPORT_ENABLED: "false",
      RUSTFS_OBS_PROFILING_EXPORT_ENABLED: "false"}) and
  any(.[]; .kind == "NetworkPolicy" and any(.spec.egress[]?;
    .to[0].namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "observability" and .ports == [{protocol:"TCP",port:4318}]))
' "$work/production.json" >/dev/null
# Production publishes the in-cluster endpoint and buckets and takes new
# placements from Garage, admits only its three client namespaces, and lets the service user read
# drive space for archive admission.
jq -e '
  any(.[]; .kind == "ExternalSecret" and .metadata.namespace == "tuist" and
    (.spec.target.template.data["targets.json"] | fromjson | .["rustfs-gra-production-v1"] |
      .private_endpoint == "http://rustfs-s3.rustfs-production.svc.cluster.local:9000" and
      .private_network_ready == true and .archive_bucket == "sandbox-archives" and
      .archive_capacity == "rustfs" and .actions_cache_bucket == "actions-cache" and
      .actions_cache_bytes == 500000000000)) and
  any(.[]; .kind == "ExternalSecret" and .metadata.namespace == "tuist" and
    (.spec.target.template.data["targets.json"] | fromjson |
      (.["gra-production-v1"] | .access == "private" and .private_network_ready == false and .site == "gra" and
        .endpoint == "http://rustfs-s3.rustfs-production.svc.cluster.local:9000" and (has("private_endpoint") | not) and
        .bucket == "shards" and .archive_bucket == "sandbox-archives" and .actions_cache_bucket == "actions-cache" and
        .access_key_id == "{{ .access_key_id }}") and
      (keys == ["gra-production-v1", "rustfs-gra-production-v1"]))) and
  any(.[]; .kind == "NetworkPolicy" and .metadata.name == "rustfs-store" and
    ([.spec.ingress[].from[] | .namespaceSelector.matchLabels["kubernetes.io/metadata.name"] // empty] | sort) ==
      ["tuist", "tuist-runners", "tuist-sandboxes"]) and
  any(.[]; .kind == "ConfigMap" and .metadata.name == "rustfs-setup" and
    (.data["policy.json"] | fromjson | .Statement | map(.Resource) | flatten | sort) ==
      ["arn:aws:s3:::*", "arn:aws:s3:::actions-cache", "arn:aws:s3:::actions-cache/*",
       "arn:aws:s3:::sandbox-archives", "arn:aws:s3:::sandbox-archives/*", "arn:aws:s3:::shards", "arn:aws:s3:::shards/*"] and
    (.data["archive-lifecycle.json"] | fromjson | .Rules[0] | has("Expiration") | not)) and
  any(.[]; .kind == "CronJob" and (.spec.jobTemplate.spec.template.spec.containers[0].args[0] |
    contains("mc quota set admin/actions-cache --size 500GB")))
' "$work/production.json" >/dev/null
# The gateway logs every proxied request to stdout, and no log names the query
# string (presigned signatures) or a credential header. The ingress stays
# silent, since its format logs the whole request line.
conf=$(jq -r '.[] | select(.kind == "ConfigMap" and .metadata.name == "rustfs-gateway") | .data["default.conf"]' "$work/production.json")
vars=$(grep -o "log_format rustfs_access .*';" <<<"$conf" | grep -o '\$[a-z0-9_]*' | sort -u | tr '\n' ' ')
if [ "$vars" != '$bytes_sent $http_user_agent $remote_addr $request_length $request_method $request_time $rustfs_auth $rustfs_client $rustfs_key_id $status $time_iso8601 $uri ' ]; then
  echo "FAIL: gateway access log names unexpected variables: $vars" >&2; exit 1
fi
if [ "$(grep -c 'log_format' <<<"$conf")" != 1 ] ||
  [ "$(grep -o 'access_log [^;]*;' <<<"$conf" | sort | tr '\n' ' ')" != 'access_log /dev/stdout rustfs_access; access_log off; ' ] ||
  ! grep -q 'location = /ready { access_log off; return 200; }' <<<"$conf" ||
  [ "$(grep -o 'error_log [^;]*;' <<<"$conf")" != 'error_log /dev/null;' ]; then
  echo 'FAIL: gateway must log requests only in the rustfs_access format and keep its error log off' >&2; exit 1
fi
jq -e 'any(.[]; .kind == "Ingress" and .metadata.annotations["nginx.ingress.kubernetes.io/enable-access-log"] == "false")' \
  "$work/production.json" >/dev/null
# The key ID maps capture exactly the access key ID, hyphenated like the
# chart's own, and nothing from a crafted credential. Like nginx's map, the
# first regex that matches wins and its $1 is the value.
key_id() { # map variable, input
  sed -n "/^ *map [^ ]* \\\$$1 {/,/^ *}\$/p" <<<"$conf" | sed -n 's/^ *"~\(.*\)" \$1;$/\1/p' |
    perl -e 'my $in = shift; while (my $re = <STDIN>) { chomp $re; if ($in =~ /$re/) { print $1; exit } }' "$2"
}
sig=5ec7e75191a7e1b2c0ffee0123456789abcdef0123456789abcdef0123456789
for check in \
  "rustfs_query_key_id|X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=rustfs-shards%2F20261125%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Signature=$sig|rustfs-shards" \
  "rustfs_query_key_id|AWSAccessKeyId=rustfs-shards&Expires=1&Signature=$sig|rustfs-shards" \
  "rustfs_query_key_id|X-Amz-Credential=rustfs-shards=X-Amz-Signature=$sig%2F|" \
  "rustfs_key_id|AWS4-HMAC-SHA256 Credential=rustfs-shards/20261125/us-east-1/s3/aws4_request, SignedHeaders=host, Signature=$sig|rustfs-shards" \
  "rustfs_key_id|AWS rustfs-shards:c2lnbmF0dXJl=|rustfs-shards" \
  "rustfs_key_id|AWS4-HMAC-SHA256 Credential=rustfs-shards,Signature=$sig/x|"; do
  IFS='|' read -r map input want <<<"$check"
  got=$(key_id "$map" "$input")
  if [ "$got" != "$want" ]; then
    echo "FAIL: \$$map for '$input' is '$got', expected '$want'" >&2; exit 1
  fi
done
# Every S3 request, in-cluster ones included, reaches a loopback audit sidecar
# that ships the receiver in files/. The sidecar has no probes and restarts the
# receiver in place, so a crash does not make the store pod NotReady.
jq -e --rawfile receiver "$chart/files/audit_receiver.py" '
  any(.[]; .kind == "ConfigMap" and .metadata.name == "rustfs-audit-receiver" and
    (.data["audit_receiver.py"] | rtrimstr("\n")) == ($receiver | rtrimstr("\n"))) and
  any(.[]; .kind == "StatefulSet" and
    ([.spec.template.spec.containers[0].env[] | select(.name | test("^RUSTFS_(AUDIT|OUTBOUND)_")) | {(.name): .value}] | add) == {
      RUSTFS_AUDIT_ENABLE: "true",
      RUSTFS_AUDIT_WEBHOOK_ENABLE_PULSE: "on",
      RUSTFS_AUDIT_WEBHOOK_ENDPOINT_PULSE: "http://127.0.0.1:9900/audit",
      RUSTFS_AUDIT_WEBHOOK_QUEUE_DIR_PULSE: "/audit-queue",
      RUSTFS_AUDIT_WEBHOOK_QUEUE_LIMIT_PULSE: "10000",
      RUSTFS_OUTBOUND_ALLOW_ORIGINS: "http://127.0.0.1:9900"} and
    any(.spec.template.spec.volumes[]; .name == "audit-queue" and .emptyDir.sizeLimit == "2Gi") and
    any(.spec.template.spec.containers[0].volumeMounts[]; .name == "audit-queue" and .mountPath == "/audit-queue") and
    (.spec.template.spec.containers[1] | .name == "audit" and
      (.command | join(" ") | contains("while :; do python3 -I -B /app/audit_receiver.py 9900 &")) and
      .securityContext.readOnlyRootFilesystem == true and
      (has("readinessProbe") or has("livenessProbe") or has("startupProbe") | not)))
' "$work/production.json" >/dev/null
helm template rustfs "$chart" -n rustfs-staging --set enabled=true --set audit.enabled=false |
  yq -o json -I0 'select(.kind != null)' | jq -s . >"$work/no-audit.json"
jq -e 'all(.[] | select(.kind == "StatefulSet"); (.spec.template.spec.containers | length) == 1 and
    all(.spec.template.spec.containers[0].env[]; .name | test("^RUSTFS_(AUDIT|OUTBOUND)_") | not)) and
  all(.[]; .metadata.name != "rustfs-audit-receiver")' "$work/no-audit.json" >/dev/null
if helm template rustfs "$chart" -n rustfs-production -f "$chart/values-production-gra.yaml" \
  --set privateNetwork.enabled=false --set target.privateNetworkReady=true >/dev/null 2>&1; then
  echo 'FAIL: private placement accepted without a private network' >&2; exit 1
fi
# Without metricsEndpoint, nothing is exported and no egress opens.
helm template rustfs "$chart" -n rustfs-staging --set enabled=true |
  yq -o json -I0 'select(.kind != null)' | jq -s . >"$work/no-metrics.json"
jq -e 'all(.[] | select(.kind == "StatefulSet") | .spec.template.spec.containers[0].env[]; (.name | startswith("RUSTFS_OBS_")) | not) and
  all(.[] | select(.kind == "NetworkPolicy") | .spec.egress[]?.to[]?; .namespaceSelector.matchLabels["kubernetes.io/metadata.name"] != "observability")
' "$work/no-metrics.json" >/dev/null
if helm template rustfs "$chart" -n rustfs-production -f "$chart/values-production-gra.yaml" \
  --set privateNetwork.enabled=false --set target.privateNetworkReady=false >/dev/null 2>&1; then
  echo 'FAIL: alias published without a private network' >&2; exit 1
fi
if helm template rustfs "$chart" -n rustfs-staging --set enabled=true --set target.id=x >/dev/null 2>&1; then
  echo 'FAIL: target published without generated credentials and a public host or runner entrances' >&2; exit 1
fi
# The rack Macs' store: private, on larch-store-a, reached through each rack
# site's gateway on that site's segment, published to Macs only once ready.
helm template rustfs-larch "$chart" -n rustfs-larch -f "$chart/values-production-larch.yaml" |
  yq -o json -I0 'select(.kind != null)' | jq -s . >"$work/larch.json"
jq -e '
  all(.[] | select(.kind == "StatefulSet" or .kind == "Deployment");
    .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "rack-storage-larch" and
    .spec.template.spec.tolerations[0].key == "tuist.dev/rack-storage") and
  ([.[] | select(.kind == "Ingress") | {class: .spec.ingressClassName, host: .spec.rules[0].host,
    target: .metadata.annotations["external-dns.alpha.kubernetes.io/target"],
    allow: .metadata.annotations["nginx.ingress.kubernetes.io/whitelist-source-range"],
    paths: [.spec.rules[0].http.paths[].path], buffer: .metadata.annotations["nginx.ingress.kubernetes.io/proxy-request-buffering"]}] |
    sort_by(.host)) == [
      {class: "kura-ber1-runners", host: "s3-larch-via-ber1.tuist.dev", target: "10.10.0.11", allow: "10.10.0.0/24", paths: ["/shards"], buffer: "off"},
      {class: "kura-larch-runners", host: "s3-larch.tuist.dev", target: "10.20.0.11", allow: "10.20.0.0/24", paths: ["/shards"], buffer: "off"}] and
  any(.[]; .kind == "ExternalSecret" and .metadata.namespace == "tuist" and .spec.target.name == "rustfs-larch-targets" and
    (.spec.target.template.data["targets.json"] | fromjson | keys == ["rustfs-larch-production-v1"] and
      (.["rustfs-larch-production-v1"] | .access == "private" and .site == "larch" and .private_network_ready == false and
        .endpoint == "http://rustfs-larch-s3.rustfs-larch.svc.cluster.local:9000" and
        .runner_endpoints == {larch: "https://s3-larch.tuist.dev", ber1: "https://s3-larch-via-ber1.tuist.dev"}))) and
  any(.[]; .kind == "CiliumNetworkPolicy" and .spec.ingress[0].fromEntities == ["host", "remote-node"]) and
  any(.[]; .kind == "NetworkPolicy" and .metadata.name == "rustfs-larch-store" and
    ([.spec.ingress[].from[] | .namespaceSelector.matchLabels["kubernetes.io/metadata.name"] // empty]) == ["tuist"])
' "$work/larch.json" >/dev/null
helm template rustfs-larch "$chart" -n rustfs-larch -f "$chart/values-production-larch.yaml" --set target.runnerEntrancesReady=false |
  yq -o json -I0 'select(.kind == "ExternalSecret" and .metadata.name == "rustfs-larch-targets")' |
  jq -e '.spec.target.template.data["targets.json"] | fromjson | .["rustfs-larch-production-v1"] | has("runner_endpoints") | not' >/dev/null
if helm template rustfs-larch "$chart" -n rustfs-larch -f "$chart/values-production-larch.yaml" \
  --set privateNetwork.enabled=false >/dev/null 2>&1; then
  echo 'FAIL: runner entrances accepted without the in-cluster endpoint' >&2; exit 1
fi
echo 'PASS: rack Macs store: private target on larch-store-a, an entrance per rack site, published only once ready'
echo 'PASS: production GRA store: one 1000G drive, generated credentials, in-cluster setup, public target, OTLP drive metrics, query-free gateway access log, scrubbed audit sidecar, private endpoint with archive and Actions cache buckets'
echo 'PASS: single-member OVH performance variant: one member, eight drives, EC:4, kura-eu-west ingress'
echo 'PASS: disabled defaults, isolation, eight volumes, four hosts, EC:4, retained PVCs, streaming gateway and restricted services'
