#!/usr/bin/env bash
set -euo pipefail
chart="$(dirname "${BASH_SOURCE[0]}")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
helm lint "$chart" --namespace observability
helm template pulse "$chart" --namespace observability > "$tmp/rendered.yaml"
yq ea -o=json -I=0 '.' "$tmp/rendered.yaml" | jq -s 'map(select(. != null))' > "$tmp/resources.json"
jq -e '
  length == 6 and
  all(.[]; .kind != "Secret" and .kind != "Ingress" and .kind != "ClusterRole") and
  any(.[]; .kind == "Service" and .spec.type == "ClusterIP" and (.spec.ports | length) == 1) and
  any(.[]; .kind == "StatefulSet" and .spec.replicas == 1 and
    .spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "general" and
    .spec.template.spec.automountServiceAccountToken == false and
    .spec.persistentVolumeClaimRetentionPolicy == {whenDeleted:"Retain",whenScaled:"Retain"} and
    .spec.volumeClaimTemplates[0].spec.resources.requests.storage == "10Gi" and
    .spec.template.spec.containers[0].image == "ghcr.io/tuist/pulse:1.44.0-canary.1" and
    .spec.template.spec.containers[0].readinessProbe.httpGet.path == "/health" and
    .spec.template.spec.containers[0].envFrom[0].secretRef.name == "pulse-credentials") and
  any(.[]; .kind == "ConfigMap" and
    (.data["config.toml"] | contains("provider = \"raft_engine\"", "root = \"pulse/\"", "type = \"S3\"", "user_provider = \"static_user_provider:file:"))) and
  any(.[]; .kind == "ExternalSecret" and
    ([.spec.data[].remoteRef.key] | sort) == ["PULSE_S3_CREDENTIALS/access_key_id","PULSE_S3_CREDENTIALS/secret_access_key"]) and
  any(.[]; .kind == "NetworkPolicy" and .spec.ingress[0].from == [{podSelector:{}}]) and
  # The host-network control-plane collector reaches only the HTTP API.
  any(.[]; .kind == "CiliumNetworkPolicy" and .metadata.name == "pulse-host-ingress" and
    .spec.endpointSelector == {matchLabels:{"app.kubernetes.io/instance":"pulse"}} and
    .spec.ingress == [{fromEntities:["host","remote-node"],toPorts:[{ports:[{port:"4000",protocol:"TCP"}]}]}])
' "$tmp/resources.json" > /dev/null
for setting in storage.prefix=tenants/ storage.bucket=tuist-pulso-production; do
  if helm template pulse "$chart" -n observability --set "$setting" > "$tmp/refused.log" 2>&1; then
    echo "FAIL: unsafe storage setting accepted: $setting" >&2
    exit 1
  fi
  grep -Fq "selected environment's bucket and isolated prefix" "$tmp/refused.log"
done
# Standalone remains for the staging/canary pilots; production is covered below.
for environment in staging canary; do
  ns="tuist-$environment"
  helm template pulse "$chart" -n observability \
    --set "environment=$environment,storage.bucket=tuist-pulso-$environment,dashboard.enabled=true" > "$tmp/scoped.yaml"
  yq ea -o=json -I=0 '.' "$tmp/scoped.yaml" | jq -s --arg ns "$ns" '
    map(select(. != null)) |
    length == 7 and
    any(.[]; .kind == "ExternalSecret" and .metadata.name == "pulse-dashboard-auth" and
      .spec.data[0].remoteRef.key == "PULSE_TOKEN/password" and
      (.spec.target.template.data.passwd | contains("dashboard:ro=", "tuist:wo=")) and
      .spec.target.template.data["ingest-username"] == "tuist" and
      (.spec.target.template.data["ingest-password"] | contains(".token"))) and
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
if helm template pulse "$chart" -n observability --set environment=other > /dev/null 2>&1; then exit 1; fi
if helm template pulse "$chart" -n default > /dev/null 2>&1; then exit 1; fi
# Production must never render the single-node standalone backend.
for refused in "--set environment=production,storage.bucket=tuist-pulso-production" \
  "-f $chart/values-production.yaml --set topology=standalone" \
  "-f $chart/values-production.yaml --set cluster.datanode.replicas=2" \
  "-f $chart/values-production.yaml --set cluster.frontend.replicas=1"; do
  # shellcheck disable=SC2086
  if helm template pulse "$chart" -n observability $refused > /dev/null 2>&1; then
    echo "FAIL: unsafe production topology accepted: $refused" >&2
    exit 1
  fi
done
helm lint "$chart" --namespace observability -f "$chart/values-production.yaml" > /dev/null
helm template pulse "$chart" -n observability -f "$chart/values-production.yaml" \
  --set dashboard.enabled=true > "$tmp/prod.yaml"
yq ea -o=json -I=0 '.' "$tmp/prod.yaml" | jq -s 'map(select(. != null))' > "$tmp/prod.json"
jq -e '
  def one(kind; name): [.[] | select(.kind == kind and .metadata.name == name)] | select(length == 1) | .[0];
  def config(name): one("ConfigMap"; name).data | to_entries[0].value;
  def spread(component): .spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution ==
    [{topologyKey:"kubernetes.io/hostname",labelSelector:{matchLabels:{"app.kubernetes.io/instance":"pulse","app.kubernetes.io/component":component}}}];
  all(.[]; .kind != "Secret" and .kind != "Ingress" and .kind != "ClusterRole") and
  ([.[] | select(.kind == "StatefulSet" or .kind == "Deployment")] | length == 5 and all(.[];
    .spec.template.spec.nodeSelector == {"node.cluster.x-k8s.io/pool":"general"} and
    .spec.template.spec.automountServiceAccountToken == false)) and
  ([.[] | select(.kind == "StatefulSet")] | all(.[]; .spec.persistentVolumeClaimRetentionPolicy == {whenDeleted:"Retain",whenScaled:"Retain"})) and
  (one("StatefulSet"; "pulse-etcd") | .spec.replicas == 3 and spread("etcd")) and
  (one("StatefulSet"; "pulse-kafka") | .spec.replicas == 3 and spread("kafka") and
    (.spec.template.spec.containers[0].image | test("^docker.io/apache/kafka:[0-9.]+@sha256:[0-9a-f]{64}$"))) and
  (one("Deployment"; "pulse-metasrv") | .spec.replicas == 3 and spread("metasrv")) and
  (one("StatefulSet"; "pulse-datanode") | .spec.replicas == 3 and spread("datanode") and
    .spec.template.spec.containers[0].image == "ghcr.io/tuist/pulse:1.44.0-canary.1" and
    .spec.template.spec.containers[0].envFrom[0].secretRef.name == "pulse-credentials") and
  (one("Deployment"; "pulse-frontend") | .spec.replicas == 2 and spread("frontend") and
    .spec.template.spec.initContainers[0].name == "combine-auth") and
  ([.[] | select(.kind == "PodDisruptionBudget") | .spec.maxUnavailable] == [1,1,1,1,1]) and
  # Readers keep the standalone Service name, now served by the frontends.
  (one("Service"; "pulse") | .spec.type == "ClusterIP" and .spec.selector["app.kubernetes.io/component"] == "frontend") and
  (one("ExternalSecret"; "pulse-credentials").spec.target.template.data | keys ==
    ["PULSE_DATANODE__STORAGE__ACCESS_KEY_ID","PULSE_DATANODE__STORAGE__SECRET_ACCESS_KEY"]) and
  (config("pulse-kafka-config") | contains("min.insync.replicas=2", "default.replication.factor=3",
    "unclean.leader.election.enable=false", "auto.create.topics.enable=false", "log.retention.ms=-1")) and
  (config("pulse-metasrv-config") | contains("backend = \"etcd_store\"", "provider = \"kafka\"",
    "replication_factor = 3", "enable_region_failover = true", "allow_region_failover_on_local_wal = false")) and
  (config("pulse-datanode-config") | contains("provider = \"kafka\"", "overwrite_entry_start_id = false",
    "bucket = \"tuist-pulso-production\"", "root = \"pulse/distributed/\"") and (contains("raft_engine") | not)) and
  (config("pulse-frontend-config") | contains("user_provider = \"static_user_provider:file:")) and
  (one("NetworkPolicy"; "pulse-internal").spec.ingress == [{from:[{podSelector:{matchLabels:{"app.kubernetes.io/instance":"pulse"}}}]}]) and
  (one("NetworkPolicy"; "pulse-private") | .spec.podSelector.matchLabels["app.kubernetes.io/component"] == "frontend" and
    .spec.ingress[1].from[0].namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "tuist") and
  (one("CiliumNetworkPolicy"; "pulse-host-ingress") |
    .spec.endpointSelector == {matchLabels:{"app.kubernetes.io/instance":"pulse","app.kubernetes.io/component":"frontend"}} and
    .spec.ingress == [{fromEntities:["host","remote-node"],toPorts:[{ports:[{port:"4000",protocol:"TCP"}]}]}])
' "$tmp/prod.json" > /dev/null
# Each workload restarts exactly when its own rendered config changes.
checksums() {
  helm template pulse "$1" -n observability -f "$chart/values-production.yaml" "${@:2}" |
    yq ea -o=json -I=0 'select(.kind == "StatefulSet" or .kind == "Deployment") |
      {(.metadata.name): (.spec.template.metadata.annotations["checksum/config"] // "")}' | jq -s -c 'add'
}
baseline=$(checksums "$chart")
cp -R "$chart" "$tmp/edited"
# Template-only edits: one Kafka setting and one metasrv WAL setting.
sed -e 's/^min.insync.replicas=2$/min.insync.replicas=3/' -e 's/^num_topics = 16$/num_topics = 32/' \
  "$chart/templates/_cluster-config.tpl" > "$tmp/edited/templates/_cluster-config.tpl"
jq -e -n --argjson before "$baseline" --argjson after "$(checksums "$tmp/edited")" '
  ([$before["pulse-kafka", "pulse-metasrv", "pulse-datanode", "pulse-frontend"]] | all(length == 16)) and
  ($after | to_entries | length == 5) and
  ($before["pulse-kafka"] != $after["pulse-kafka"]) and
  ($before["pulse-metasrv"] != $after["pulse-metasrv"]) and
  ($before["pulse-datanode"] == $after["pulse-datanode"]) and
  ($before["pulse-frontend"] == $after["pulse-frontend"])' > /dev/null
jq -e -n --argjson before "$baseline" --argjson after "$(checksums "$chart" --set cluster.frontend.replicas=3)" \
  '$before == $after' > /dev/null
# Management: standalone on one node's hostPath, its own bucket, no Cilium
# policy, readers limited to its own PDC agent, and no unsafe overrides.
# Render it the way Flux does: valuesFiles are merged into the chart's own
# defaults (where a null would survive as a value), not passed as user values.
cp -R "$chart" "$tmp/flux-chart"
yq ea '. as $item ireduce ({}; . * $item)' "$chart/values.yaml" "$chart/values-management.yaml" > "$tmp/flux-chart/values.yaml"
helm template pulse "$tmp/flux-chart" -n observability > "$tmp/mgmt.yaml"
yq ea -o=json -I=0 '.' "$tmp/mgmt.yaml" | jq -s '
  map(select(. != null)) |
  all(.[]; .kind != "CiliumNetworkPolicy") and
  any(.[]; .kind == "StatefulSet" and (.spec | has("volumeClaimTemplates") | not) and
    .spec.template.spec.nodeSelector == {"kubernetes.io/hostname":"tuist-mgmt"} and
    any(.spec.template.spec.volumes[]; .name == "data" and .hostPath.path == "/var/lib/tuist-pulse") and
    ([.spec.template.spec.initContainers[].name] == ["own-data","combine-auth"])) and
  any(.[]; .kind == "ConfigMap" and (.data["config.toml"] | contains("bucket = \"tuist-pulso-production\"", "root = \"management/\""))) and
  any(.[]; .kind == "NetworkPolicy" and (.spec.ingress | length) == 2 and
    .spec.ingress[1].from == [{namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":"observability"}},
      podSelector:{matchLabels:{"app.kubernetes.io/name":"pdc-agent","app.kubernetes.io/instance":"pulse","app.kubernetes.io/component":"pdc-agent"}}}])
' | grep -qx true
for refused in topology=cluster persistence.hostPath= nodeSelector=null storage.prefix=pulse/ storage.bucket=tuist-pulso-staging; do
  if helm template pulse "$chart" -n observability -f "$chart/values-management.yaml" --set "$refused" > /dev/null 2>&1; then
    echo "FAIL: unsafe management setting accepted: $refused" >&2
    exit 1
  fi
done
if helm template pulse "$chart" -n observability --set environment=management,storage.bucket=tuist-pulso-management > /dev/null 2>&1; then exit 1; fi
echo 'PASS: per-environment private backend, scoped auth, isolated S3 prefix, retained WAL volume, HA production topology and hostPath management backend'
