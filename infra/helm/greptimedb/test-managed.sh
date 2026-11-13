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
# Standalone remains for the staging/canary pilots; production is covered below.
for environment in staging canary; do
  ns="tuist-$environment"
  helm template greptimedb "$chart" -n observability \
    --set "environment=$environment,storage.bucket=tuist-pulso-$environment,dashboard.enabled=true" > "$tmp/scoped.yaml"
  yq ea -o=json -I=0 '.' "$tmp/scoped.yaml" | jq -s --arg ns "$ns" '
    map(select(. != null)) |
    length == 6 and
    any(.[]; .kind == "ExternalSecret" and .metadata.name == "greptimedb-dashboard-auth" and
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
if helm template greptimedb "$chart" -n observability --set environment=other > /dev/null 2>&1; then exit 1; fi
if helm template greptimedb "$chart" -n default > /dev/null 2>&1; then exit 1; fi
# Production must never render the single-node standalone backend.
for refused in "--set environment=production,storage.bucket=tuist-pulso-production" \
  "-f $chart/values-production.yaml --set topology=standalone" \
  "-f $chart/values-production.yaml --set cluster.datanode.replicas=2" \
  "-f $chart/values-production.yaml --set cluster.frontend.replicas=1"; do
  # shellcheck disable=SC2086
  if helm template greptimedb "$chart" -n observability $refused > /dev/null 2>&1; then
    echo "FAIL: unsafe production topology accepted: $refused" >&2
    exit 1
  fi
done
helm lint "$chart" --namespace observability -f "$chart/values-production.yaml" > /dev/null
helm template greptimedb "$chart" -n observability -f "$chart/values-production.yaml" \
  --set dashboard.enabled=true > "$tmp/prod.yaml"
yq ea -o=json -I=0 '.' "$tmp/prod.yaml" | jq -s 'map(select(. != null))' > "$tmp/prod.json"
jq -e '
  def one(kind; name): [.[] | select(.kind == kind and .metadata.name == name)] | select(length == 1) | .[0];
  def config(name): one("ConfigMap"; name).data | to_entries[0].value;
  def spread(component): .spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution ==
    [{topologyKey:"kubernetes.io/hostname",labelSelector:{matchLabels:{"app.kubernetes.io/instance":"greptimedb","app.kubernetes.io/component":component}}}];
  all(.[]; .kind != "Secret" and .kind != "Ingress" and .kind != "ClusterRole") and
  ([.[] | select(.kind == "StatefulSet" or .kind == "Deployment")] | length == 5 and all(.[];
    .spec.template.spec.nodeSelector == {"node.cluster.x-k8s.io/pool":"general"} and
    .spec.template.spec.automountServiceAccountToken == false)) and
  ([.[] | select(.kind == "StatefulSet")] | all(.[]; .spec.persistentVolumeClaimRetentionPolicy == {whenDeleted:"Retain",whenScaled:"Retain"})) and
  (one("StatefulSet"; "greptimedb-etcd") | .spec.replicas == 3 and spread("etcd")) and
  (one("StatefulSet"; "greptimedb-kafka") | .spec.replicas == 3 and spread("kafka") and
    (.spec.template.spec.containers[0].image | test("^docker.io/apache/kafka:[0-9.]+@sha256:[0-9a-f]{64}$"))) and
  (one("Deployment"; "greptimedb-metasrv") | .spec.replicas == 3 and spread("metasrv")) and
  (one("StatefulSet"; "greptimedb-datanode") | .spec.replicas == 3 and spread("datanode") and
    .spec.template.spec.containers[0].image == "docker.io/greptime/greptimedb:v1.3.0" and
    .spec.template.spec.containers[0].envFrom[0].secretRef.name == "greptimedb-credentials") and
  (one("Deployment"; "greptimedb-frontend") | .spec.replicas == 2 and spread("frontend") and
    .spec.template.spec.initContainers[0].name == "combine-auth") and
  ([.[] | select(.kind == "PodDisruptionBudget") | .spec.maxUnavailable] == [1,1,1,1,1]) and
  # Readers keep the standalone Service name, now served by the frontends.
  (one("Service"; "greptimedb") | .spec.type == "ClusterIP" and .spec.selector["app.kubernetes.io/component"] == "frontend") and
  (one("ExternalSecret"; "greptimedb-credentials").spec.target.template.data | keys ==
    ["GREPTIMEDB_DATANODE__STORAGE__ACCESS_KEY_ID","GREPTIMEDB_DATANODE__STORAGE__SECRET_ACCESS_KEY"]) and
  (config("greptimedb-kafka-config") | contains("min.insync.replicas=2", "default.replication.factor=3",
    "unclean.leader.election.enable=false", "auto.create.topics.enable=false", "log.retention.ms=-1")) and
  (config("greptimedb-metasrv-config") | contains("backend = \"etcd_store\"", "provider = \"kafka\"",
    "replication_factor = 3", "enable_region_failover = true", "allow_region_failover_on_local_wal = false")) and
  (config("greptimedb-datanode-config") | contains("provider = \"kafka\"", "overwrite_entry_start_id = false",
    "bucket = \"tuist-pulso-production\"", "root = \"greptimedb/distributed/\"") and (contains("raft_engine") | not)) and
  (config("greptimedb-frontend-config") | contains("user_provider = \"static_user_provider:file:")) and
  (one("NetworkPolicy"; "greptimedb-internal").spec.ingress == [{from:[{podSelector:{matchLabels:{"app.kubernetes.io/instance":"greptimedb"}}}]}]) and
  (one("NetworkPolicy"; "greptimedb-private") | .spec.podSelector.matchLabels["app.kubernetes.io/component"] == "frontend" and
    .spec.ingress[1].from[0].namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "tuist")
' "$tmp/prod.json" > /dev/null
# Each workload restarts exactly when its own rendered config changes.
checksums() {
  helm template greptimedb "$1" -n observability -f "$chart/values-production.yaml" "${@:2}" |
    yq ea -o=json -I=0 'select(.kind == "StatefulSet" or .kind == "Deployment") |
      {(.metadata.name): (.spec.template.metadata.annotations["checksum/config"] // "")}' | jq -s -c 'add'
}
baseline=$(checksums "$chart")
cp -R "$chart" "$tmp/edited"
# Template-only edits: one Kafka setting and one metasrv WAL setting.
sed -e 's/^min.insync.replicas=2$/min.insync.replicas=3/' -e 's/^num_topics = 16$/num_topics = 32/' \
  "$chart/templates/_cluster-config.tpl" > "$tmp/edited/templates/_cluster-config.tpl"
jq -e -n --argjson before "$baseline" --argjson after "$(checksums "$tmp/edited")" '
  ([$before["greptimedb-kafka", "greptimedb-metasrv", "greptimedb-datanode", "greptimedb-frontend"]] | all(length == 16)) and
  ($after | to_entries | length == 5) and
  ($before["greptimedb-kafka"] != $after["greptimedb-kafka"]) and
  ($before["greptimedb-metasrv"] != $after["greptimedb-metasrv"]) and
  ($before["greptimedb-datanode"] == $after["greptimedb-datanode"]) and
  ($before["greptimedb-frontend"] == $after["greptimedb-frontend"])' > /dev/null
jq -e -n --argjson before "$baseline" --argjson after "$(checksums "$chart" --set cluster.frontend.replicas=3)" \
  '$before == $after' > /dev/null
echo 'PASS: per-environment private backend, scoped auth, isolated S3 prefix, retained WAL volume and HA production topology'
