#!/usr/bin/env bash
set -euo pipefail
chart="$(dirname "${BASH_SOURCE[0]}")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
helm lint "$chart" --namespace observability
helm template pulse "$chart" --namespace observability > "$tmp/rendered.yaml"
yq ea -o=json -I=0 '.' "$tmp/rendered.yaml" | jq -s 'map(select(. != null))' > "$tmp/resources.json"
# Every workload cluster runs the cluster topology; the defaults size it for
# staging and canary.
jq -e '
  def one(kind; name): [.[] | select(.kind == kind and .metadata.name == name)] | select(length == 1) | .[0];
  all(.[]; .kind != "Secret" and .kind != "Ingress" and .kind != "ClusterRole") and
  ([.[] | select(.kind == "StatefulSet" or .kind == "Deployment") | .metadata.name] | sort ==
    ["pulse-datanode","pulse-etcd","pulse-flownode","pulse-frontend","pulse-kafka","pulse-metasrv"]) and
  (one("StatefulSet"; "pulse-datanode").spec.template.spec.containers[0] |
    .image == "ghcr.io/tuist/pulse:1.44.0-canary.4" and .resources.requests == {cpu:"250m",memory:"768Mi"}) and
  (one("StatefulSet"; "pulse-kafka") | .spec.volumeClaimTemplates[0].spec.resources.requests.storage == "10Gi" and
    any(.spec.template.spec.containers[0].env[]; .name == "KAFKA_HEAP_OPTS" and .value == "-Xms512m -Xmx512m")) and
  (one("Service"; "pulse").spec.selector == {"app.kubernetes.io/instance":"pulse","app.kubernetes.io/component":"frontend"}) and
  # Outside a migration there is no standalone backend or qualification Service.
  all(.[]; .metadata.name != "pulse" or .kind == "Service") and
  all(.[]; .metadata.name != "pulse-frontend" or .kind != "Service")
' "$tmp/resources.json" > /dev/null
# Every workload cluster holds its datanodes for pulse-datanode-rollout.sh, so
# no restart relies on region failover, which never moves regions back.
for environment in staging canary production; do
  values="$chart/values.yaml"
  [[ "$environment" == production ]] && values="$chart/values-production.yaml"
  helm template pulse "$chart" -n observability -f "$values" \
    --set "environment=$environment,storage.bucket=tuist-pulso-$environment" |
    yq ea -o=json -I=0 'select(.kind == "StatefulSet" and .metadata.name == "pulse-datanode") | .spec.updateStrategy' |
    jq -e '. == {type: "RollingUpdate", rollingUpdate: {partition: 3}}' > /dev/null
done
for setting in storage.prefix=tenants/ storage.bucket=tuist-pulso-production; do
  if helm template pulse "$chart" -n observability --set "$setting" > "$tmp/refused.log" 2>&1; then
    echo "FAIL: unsafe storage setting accepted: $setting" >&2
    exit 1
  fi
  grep -Fq "selected environment's bucket and isolated prefix" "$tmp/refused.log"
done
for environment in staging canary; do
  ns="tuist-$environment"
  helm template pulse "$chart" -n observability \
    --set "environment=$environment,storage.bucket=tuist-pulso-$environment,dashboard.enabled=true" > "$tmp/scoped.yaml"
  yq ea -o=json -I=0 '.' "$tmp/scoped.yaml" | jq -s --arg ns "$ns" '
    def one(kind; name): [.[] | select(.kind == kind and .metadata.name == name)] | select(length == 1) | .[0];
    map(select(. != null)) |
    (one("ExternalSecret"; "pulse-dashboard-auth") |
      .spec.data[0].remoteRef.key == "PULSE_TOKEN/password" and
      (.spec.target.template.data.passwd | contains("dashboard:ro=", "tuist:wo=")) and
      # values.yaml opts every managed environment into the Sentry writer and
      # the Symptoms reader.
      (.spec.data | length) == 3 and
      (.spec.target.template.data.passwd | contains("sentry")) and
      (.spec.target.template.data.passwd | contains("\nsymptoms:ro=")) and
      .spec.target.template.data["ingest-username"] == "tuist" and
      (.spec.target.template.data["ingest-password"] | contains(".token"))) and
    # Grafana reads every workload Pulse over PostgreSQL through the PDC agent,
    # which alone may reach 4003 (ingress[2] below).
    (one("Service"; "pulse") | any(.spec.ports[]; .name == "postgres" and .port == 4003)) and
    (one("Deployment"; "pulse-frontend").spec.template.spec |
      .initContainers[0].name == "combine-auth" and
      any(.volumes[]; .name == "auth-inputs" and (.projected.sources | length) == 2)) and
    (one("NetworkPolicy"; "pulse-private").spec |
      .ingress[1].from == [{namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":$ns}},
        podSelector:{matchLabels:{"app.kubernetes.io/component":"server"}}}] and
      .ingress[2].from == [{namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":$ns}},
        podSelector:{matchLabels:{"app.kubernetes.io/name":"tuist","app.kubernetes.io/instance":"tuist","app.kubernetes.io/component":"pdc-agent"}}}] and
      .ingress[2].ports == [{port:4000,protocol:"TCP"},{port:4003,protocol:"TCP"}] and
      .ingress[3] == {ports:[{port:4000,protocol:"TCP"}], from:[
        {namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":$ns}},
         podSelector:{matchExpressions:[{key:"app.kubernetes.io/component",operator:"In",
           values:["processor","swift-registry-sync","registry"]}]}}]} and
      .ingress[4] == {ports:[{port:4000,protocol:"TCP"}], from:[
        {namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":"kura"}},
         podSelector:{matchLabels:{"app.kubernetes.io/name":"kura"}}}]} and
      .ingress[5] == {ports:[{port:4000,protocol:"TCP"}], from:[
        {namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":("symptoms-" + ($ns | ltrimstr("tuist-")))}},
         podSelector:{matchLabels:{"app.kubernetes.io/name":"symptoms","app.kubernetes.io/component":"evaluator"}}}]} and
      (.ingress | length) == 6)
  ' | grep -qx true
done
# The Sentry writer exists only in the environments listed, so a vault without
# PULSE_SENTRY_WRITER never blocks a deploy.
for environment in staging canary; do
  helm template pulse "$chart" -n observability --set-json 'sentryWriter.environments=["staging"]' \
    --set-json 'symptomsReader.environments=[]' \
    --set "environment=$environment,storage.bucket=tuist-pulso-$environment,dashboard.enabled=true" |
    yq ea -o=json -I=0 'select(.kind == "ExternalSecret" and .metadata.name == "pulse-dashboard-auth")' |
    jq -e --arg environment "$environment" '
      if $environment == "staging" then
        (.spec.target.template.data.passwd | contains("\nsentry:wo={{ .sentryWriter | trim }}\n")) and
        .spec.data[1] == {secretKey:"sentryWriter",remoteRef:{key:"PULSE_SENTRY_WRITER/password"}} and
        (.spec.data | length) == 2
      else
        (.spec.data | length) == 1 and (.spec.target.template.data.passwd | contains("sentry") | not)
      end' > /dev/null || { echo "FAIL: Sentry writer opt-in for $environment" >&2; exit 1; }
done
# The evaluator's read-only identity exists only where listed, with its own
# item, and never as a writer.
helm template pulse "$chart" -n observability --set-json 'symptomsReader.environments=["staging"]' \
  --set "environment=staging,storage.bucket=tuist-pulso-staging,dashboard.enabled=true" |
  yq ea -o=json -I=0 'select(.kind == "ExternalSecret" and .metadata.name == "pulse-dashboard-auth")' |
  jq -e '
    (.spec.target.template.data.passwd | contains("\nsymptoms:ro={{ .symptomsReader | trim }}\n")) and
    (.spec.target.template.data.passwd | contains("symptoms:wo") | not) and
    any(.spec.data[]; . == {secretKey:"symptomsReader",remoteRef:{key:"PULSE_SYMPTOMS_READER/password"}})' > /dev/null ||
  { echo "FAIL: Symptoms reader opt-in" >&2; exit 1; }
helm template pulse "$chart" -n observability --set-json 'symptomsReader.environments=[]' \
  --set "environment=canary,storage.bucket=tuist-pulso-canary,dashboard.enabled=true" |
  yq ea -o=json -I=0 'select(.kind == "ExternalSecret" and .metadata.name == "pulse-dashboard-auth")' |
  jq -e '(.spec.target.template.data.passwd | contains("symptoms") | not) and
    all(.spec.data[]; .remoteRef.key != "PULSE_SYMPTOMS_READER/password")' > /dev/null ||
  { echo "FAIL: Symptoms reader rendered without opt-in" >&2; exit 1; }
# Moving an installed standalone backend: both run side by side, the standalone
# pod keeps serving Service `pulse` until it moves to the frontends, and no
# cluster workload changes between phases.
render() { helm template pulse "$chart" -n observability --set "environment=staging,dashboard.enabled=true$1" |
  yq ea -o=json -I=0 '.' | jq -s 'map(select(. != null))'; }
render "" > "$tmp/target.json"
render ",migration.standalone=serving" > "$tmp/serving.json"
render ",migration.standalone=draining" > "$tmp/draining.json"
jq -e -n --slurpfile target "$tmp/target.json" --slurpfile serving "$tmp/serving.json" --slurpfile draining "$tmp/draining.json" '
  def one(kind; name): [.[] | select(.kind == kind and .metadata.name == name)] | select(length == 1) | .[0];
  def cluster: [.[] | select((.kind == "StatefulSet" or .kind == "Deployment") and .metadata.name != "pulse")];
  {"app.kubernetes.io/instance":"pulse","statefulset.kubernetes.io/pod-name":"pulse-0"} as $standalone |
  {"app.kubernetes.io/instance":"pulse","app.kubernetes.io/component":"frontend"} as $frontends |
  {matchLabels:{"app.kubernetes.io/instance":"pulse"},
    matchExpressions:[{key:"app.kubernetes.io/component",operator:"DoesNotExist"}]} as $policy |
  $target[0] as $target | $serving[0] as $serving | $draining[0] as $draining |
  ($serving | one("StatefulSet"; "pulse") | .spec.replicas == 1 and
    .spec.selector == {matchLabels:{"app.kubernetes.io/instance":"pulse"}} and
    .spec.persistentVolumeClaimRetentionPolicy == {whenDeleted:"Retain",whenScaled:"Retain"} and
    .spec.volumeClaimTemplates[0].spec.resources.requests.storage == "10Gi" and
    .spec.template.spec.containers[0].image == "ghcr.io/tuist/pulse:1.44.0-canary.4" and
    .spec.template.spec.containers[0].envFrom[0].secretRef.name == "pulse-credentials") and
  ($serving | one("ConfigMap"; "pulse-config").data["config.toml"] |
    contains("provider = \"raft_engine\"", "root = \"pulse/\"", "type = \"S3\"")) and
  ($serving | one("Service"; "pulse").spec.selector == $standalone) and
  ($draining | one("Service"; "pulse").spec.selector == $frontends) and
  ([$serving, $draining] | all(one("Service"; "pulse-frontend").spec.selector == $frontends)) and
  ($serving | one("ExternalSecret"; "pulse-credentials").spec.target.template.data | keys ==
    ["PULSE_DATANODE__STORAGE__ACCESS_KEY_ID","PULSE_DATANODE__STORAGE__SECRET_ACCESS_KEY",
     "PULSE_STANDALONE__STORAGE__ACCESS_KEY_ID","PULSE_STANDALONE__STORAGE__SECRET_ACCESS_KEY"]) and
  # The cluster admits only its own pods; the standalone pod keeps its readers.
  # Cilium ignores statefulset.kubernetes.io/pod-name, so policies select the
  # only Pulse pod without a component.
  ($serving | one("NetworkPolicy"; "pulse-standalone").spec |
    .podSelector == $policy and .ingress == ($serving | one("NetworkPolicy"; "pulse-private").spec.ingress)) and
  ($serving | one("CiliumNetworkPolicy"; "pulse-standalone-host-ingress").spec.endpointSelector == $policy) and
  all([$serving, $draining][][] | select(.kind | endswith("NetworkPolicy"));
    .spec | tostring | contains("statefulset.kubernetes.io/pod-name") | not) and
  # Helm applies in this order: the standalone pod gains its own policies
  # before the cluster ones select it or narrow to the frontends.
  ($serving | [.[] | select(.kind | endswith("NetworkPolicy")) | .metadata.name] |
    index("pulse-standalone") < index("pulse-internal") and index("pulse-internal") < index("pulse-private") and
    index("pulse-standalone-host-ingress") < index("pulse-host-ingress")) and
  ($serving | cluster) == ($target | cluster) and ($draining | cluster) == ($target | cluster)
' > /dev/null
if helm template pulse "$chart" -n observability --set environment=other > /dev/null 2>&1; then exit 1; fi
if helm template pulse "$chart" -n default > /dev/null 2>&1; then exit 1; fi
# Workload clusters never render the single-node standalone backend, and only
# staging and canary migrate from one.
for refused in "--set environment=production,storage.bucket=tuist-pulso-production,topology=standalone" \
  "--set topology=standalone" \
  "--set environment=canary,storage.bucket=tuist-pulso-canary,topology=standalone" \
  "--set migration.standalone=yes" \
  "-f $chart/values-production.yaml --set migration.standalone=serving" \
  "-f $chart/values-production.yaml --set topology=standalone" \
  "-f $chart/values-production.yaml --set cluster.datanode.replicas=2" \
  "-f $chart/values-production.yaml --set cluster.frontend.replicas=1"; do
  # shellcheck disable=SC2086
  if helm template pulse "$chart" -n observability $refused > /dev/null 2>&1; then
    echo "FAIL: unsafe topology accepted: $refused" >&2
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
  ([.[] | select(.kind == "StatefulSet" or .kind == "Deployment")] | length == 6 and all(.[];
    .spec.template.spec.nodeSelector == {"node.cluster.x-k8s.io/pool":"general"} and
    .spec.template.spec.automountServiceAccountToken == false)) and
  ([.[] | select(.kind == "StatefulSet")] | all(.[]; .spec.persistentVolumeClaimRetentionPolicy == {whenDeleted:"Retain",whenScaled:"Retain"})) and
  (one("StatefulSet"; "pulse-etcd") | .spec.replicas == 3 and spread("etcd")) and
  (one("StatefulSet"; "pulse-kafka") | .spec.replicas == 3 and spread("kafka") and
    (.spec.template.spec.containers[0].image | test("^docker.io/apache/kafka:[0-9.]+@sha256:[0-9a-f]{64}$"))) and
  (one("Deployment"; "pulse-metasrv") | .spec.replicas == 3 and spread("metasrv") and
    # Topic creation runs once per leader: wait for the WAL or every broker.
    .spec.template.spec.initContainers[0].name == "wait-for-wal" and
    (.spec.template.spec.initContainers[0].args[0] | contains("pulse_wal_topic_", "-ge 3"))) and
  # Production keeps its own sizing whatever the staging/canary defaults are.
  (one("StatefulSet"; "pulse-datanode").spec.template.spec.containers[0].resources == {requests:{cpu:"1500m",memory:"4Gi"},limits:{memory:"8Gi"}}) and
  (one("StatefulSet"; "pulse-kafka") | .spec.volumeClaimTemplates[0].spec.resources.requests.storage == "20Gi" and
    any(.spec.template.spec.containers[0].env[]; .name == "KAFKA_HEAP_OPTS" and .value == "-Xms1g -Xmx1g")) and
  (one("StatefulSet"; "pulse-datanode") | .spec.replicas == 3 and spread("datanode") and
    .spec.template.spec.containers[0].image == "ghcr.io/tuist/pulse:1.44.0-canary.4" and
    .spec.template.spec.containers[0].envFrom[0].secretRef.name == "pulse-credentials") and
  (one("Deployment"; "pulse-frontend") | .spec.replicas == 2 and spread("frontend") and
    .spec.template.spec.containers[0].resources == {requests:{cpu:"500m",memory:"1Gi"},limits:{memory:"4Gi"}} and
    .spec.template.spec.initContainers[0].name == "combine-auth") and
  ([.[] | select(.kind == "PodDisruptionBudget") | .spec.maxUnavailable] == [1,1,1,1,1]) and
  # Readers keep the standalone Service name, now served by the frontends.
  (one("Service"; "pulse") | .spec.type == "ClusterIP" and .spec.selector["app.kubernetes.io/component"] == "frontend") and
  (one("ExternalSecret"; "pulse-credentials").spec.target.template.data | keys ==
    ["PULSE_DATANODE__STORAGE__ACCESS_KEY_ID","PULSE_DATANODE__STORAGE__SECRET_ACCESS_KEY"]) and
  (config("pulse-kafka-config") | contains("min.insync.replicas=2", "default.replication.factor=3",
    "unclean.leader.election.enable=false", "auto.create.topics.enable=false", "log.retention.ms=-1", "log.segment.bytes=134217728")) and
  (config("pulse-metasrv-config") | contains("backend = \"etcd_store\"", "provider = \"kafka\"",
    "replication_factor = 3", "enable_region_failover = true", "allow_region_failover_on_local_wal = false")) and
  (config("pulse-datanode-config") | contains("provider = \"kafka\"", "overwrite_entry_start_id = false",
    "bucket = \"tuist-pulso-production\"", "root = \"pulse/distributed/\"") and (contains("raft_engine") | not)) and
  (config("pulse-frontend-config") | contains("user_provider = \"static_user_provider:file:", "[internal_grpc]\nbind_addr = \"0.0.0.0:4010\"")) and
  # One flownode runs the error_issues flow; it reaches the frontends on their
  # internal port, which no policy opens outside Pulse.
  (one("Deployment"; "pulse-frontend").spec.template.spec.containers[0].args | contains(["--internal-grpc-server-addr", "$(POD_IP):4010"])) and
  (one("Deployment"; "pulse-flownode") | .spec.replicas == 1 and .spec.strategy == {type:"Recreate"} and
    .spec.template.spec.containers[0].args[0:2] == ["flownode","start"]) and
  (config("pulse-flownode-config") | contains("node_id = 0", "metasrv_addrs = [\"pulse-metasrv.observability.svc.cluster.local:3002\"]")) and
  ([.[] | select(.kind == "NetworkPolicy" or .kind == "CiliumNetworkPolicy") | .. | objects | select(has("port")) | .port | tostring] |
    all(. == "4000" or . == "4003")) and
  (one("NetworkPolicy"; "pulse-internal").spec.ingress == [{from:[{podSelector:{matchLabels:{"app.kubernetes.io/instance":"pulse"}}}]}]) and
  # Only the metrics collector reaches the datanodes from outside Pulse.
  (one("NetworkPolicy"; "pulse-datanode-metrics").spec ==
    {podSelector:{matchLabels:{"app.kubernetes.io/instance":"pulse","app.kubernetes.io/component":"datanode"}},policyTypes:["Ingress"],
     ingress:[{from:[{podSelector:{matchLabels:{"app.kubernetes.io/name":"alloy-metrics"}}}],ports:[{port:4000,protocol:"TCP"}]}]}) and
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
  ([$before["pulse-kafka", "pulse-metasrv", "pulse-datanode", "pulse-flownode", "pulse-frontend"]] | all(length == 16)) and
  ($after | to_entries | length == 6) and
  ($before["pulse-kafka"] != $after["pulse-kafka"]) and
  ($before["pulse-metasrv"] != $after["pulse-metasrv"]) and
  ($before["pulse-datanode"] == $after["pulse-datanode"]) and
  ($before["pulse-frontend"] == $after["pulse-frontend"]) and
  ($before["pulse-flownode"] == $after["pulse-flownode"])' > /dev/null
jq -e -n --argjson before "$baseline" --argjson after "$(checksums "$chart" --set cluster.frontend.replicas=3)" \
  '$before == $after' > /dev/null
# Every workload cluster runs GC in both metasrv and datanodes.
for environment in staging canary production; do
  helm template pulse "$chart" -n observability --set "environment=$environment,storage.bucket=tuist-pulso-$environment" |
    yq ea -o=json -I=0 '.' | jq -s --arg env "$environment" '
      map(select(.kind == "ConfigMap")) | INDEX(.metadata.name) |
      (.["pulse-metasrv-config"].data | to_entries[0].value | test("\\[gc\\]\nenable = true\n")) as $meta |
      (.["pulse-datanode-config"].data | to_entries[0].value | test("\\[region_engine\\.mito\\.gc\\]\nenable = true\n")) as $data |
      $meta and $data
    ' | grep -qx true || { echo "FAIL: GC setting for $environment" >&2; exit 1; }
done
# pulse-gc-flip.sh's deploy stops the frontends; every other render runs them.
for stopped in false true; do
  helm template pulse "$chart" -n observability --set "cluster.frontend.stopped=$stopped" |
    yq ea -o=json -I=0 'select(.kind == "Deployment" and .metadata.name == "pulse-frontend") | .spec.replicas' |
    grep -qx "$([[ $stopped == true ]] && echo 0 || echo 2)" || { echo "FAIL: frontend replicas when stopped=$stopped" >&2; exit 1; }
done
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
  # No Sentry producer reaches management, so its vault needs no writer item.
  any(.[]; .kind == "ExternalSecret" and .metadata.name == "pulse-dashboard-auth" and
    (.spec.data | length) == 1 and (.spec.target.template.data.passwd | contains("sentry") | not)) and
  any(.[]; .kind == "StatefulSet" and (.spec | has("volumeClaimTemplates") | not) and
    .spec.template.spec.nodeSelector == {"kubernetes.io/hostname":"tuist-mgmt"} and
    any(.spec.template.spec.volumes[]; .name == "data" and .hostPath.path == "/var/lib/tuist-pulse") and
    ([.spec.template.spec.initContainers[].name] == ["own-data","combine-auth"])) and
  any(.[]; .kind == "ConfigMap" and (.data["config.toml"] | contains("bucket = \"tuist-pulso-production\"", "root = \"management/\""))) and
  any(.[]; .kind == "NetworkPolicy" and (.spec.ingress | length) == 2 and
    .spec.ingress[1].from == [{namespaceSelector:{matchLabels:{"kubernetes.io/metadata.name":"observability"}},
      podSelector:{matchLabels:{"app.kubernetes.io/name":"pdc-agent","app.kubernetes.io/instance":"pulse","app.kubernetes.io/component":"pdc-agent"}}}])
' | grep -qx true
for refused in topology=cluster migration.standalone=serving persistence.hostPath= nodeSelector=null storage.prefix=pulse/ storage.bucket=tuist-pulso-staging; do
  if helm template pulse "$chart" -n observability -f "$chart/values-management.yaml" --set "$refused" > /dev/null 2>&1; then
    echo "FAIL: unsafe management setting accepted: $refused" >&2
    exit 1
  fi
done
if helm template pulse "$chart" -n observability --set environment=management,storage.bucket=tuist-pulso-management > /dev/null 2>&1; then exit 1; fi
echo 'PASS: per-environment private backend, scoped auth, isolated S3 prefix, HA topology on every workload cluster, side-by-side standalone migration and hostPath management backend'
