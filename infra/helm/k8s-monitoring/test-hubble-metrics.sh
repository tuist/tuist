#!/usr/bin/env bash
# Exercise the rendered discovery, scrape and retention rules without a cluster.
set -euo pipefail

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
docker="${DOCKER:-docker}"
image="${ALLOY_IMAGE:-grafana/alloy:v1.15.0}"
network="hubble-metrics-$$"
fixture="${network}-fixture"
receiver="${network}-receiver"
collector="${network}-collector"
cleanup() {
  result=$?
  if (( result != 0 )); then
    for container in "${collector}" "${fixture}" "${receiver}"; do
      "${docker}" logs "${container}" 2>&1 || true
    done
  fi
  "${docker}" rm -fv "${collector}" "${fixture}" "${receiver}" >/dev/null 2>&1 || true
  "${docker}" network rm "${network}" >/dev/null 2>&1 || true
  rm -rf "${temporary}"
}
trap cleanup EXIT

helm template k8s-monitoring "${directory}" -n observability \
  -f "${directory}/values-production.yaml" > "${temporary}/rendered.yaml"
yq ea -o=json '[.]' "${temporary}/rendered.yaml" | jq -r '
  .[] | select(.kind == "ConfigMap" and (.metadata.name | endswith("alloy-metrics")))
  | .data["config.alloy"]
' > "${temporary}/metrics.alloy"

block() {
  awk -v prefix="$1" '
    !copying && index($0, prefix) {
      copying = 1
      indentation = substr($0, 1, index($0, prefix) - 1)
    }
    copying { print }
    copying && $0 == indentation "}" { exit }
    END { if (!copying) exit 1 }
  ' "${temporary}/metrics.alloy"
}

# Remove Cloud authentication and use only the isolated local receiver.
block 'prometheus.remote_write "grafana_cloud_metrics"' | awk '
  /^[[:space:]]*(headers = \{|basic_auth \{|tls_config \{)/ {
    skipping = 1
    indentation = substr($0, 1, match($0, /[^[:space:]]/) - 1)
    next
  }
  skipping {
    if ($0 == indentation "}") skipping = 0
    next
  }
  /^[[:space:]]*url = / { print "    url = \"http://receiver:9090/api/v1/write\""; next }
  { print }
' > "${temporary}/pipeline.alloy"
for component in \
  'discovery.kubernetes "tuist_hubble"' \
  'discovery.relabel "tuist_hubble"' \
  'prometheus.scrape "tuist_hubble"' \
  'prometheus.relabel "tuist_hubble"' \
  'discovery.kubernetes "services"' \
  'discovery.relabel "annotation_autodiscovery_services"'; do
  block "${component}"
done | awk '
  /^[[:space:]]*discovery.kubernetes / { discovery = 1 }
  discovery && /role = / {
    print "  api_server = \"http://fixture:8080\""
    discovery = 0
  }
  { gsub(/"60s"|"10s"/, "\"1s\""); print }
' >> "${temporary}/pipeline.alloy"
cat >> "${temporary}/pipeline.alloy" <<'ALLOY'
prometheus.scrape "service_control" {
  targets = discovery.relabel.annotation_autodiscovery_services.output
  scrape_interval = "1s"
  scrape_timeout = "1s"
  forward_to = [prometheus.remote_write.grafana_cloud_metrics.receiver]
}
ALLOY
if grep -Eq 'remote\.kubernetes|url = "https://' "${temporary}/pipeline.alloy"; then
  echo 'Fixture pipeline must not contain cluster credentials or Cloud destinations' >&2
  exit 1
fi
block 'prometheus.scrape "tuist_hubble"' | grep -q 'enabled = true'

# Nginx supplies static Kubernetes list/watch responses and distinct metrics
# ports. No custom HTTP server or host language runtime is needed.
cat > "${temporary}/nginx.conf" <<'NGINX'
pid /tmp/nginx.pid;
error_log /dev/stderr;
events {}
http {
  access_log off;
  default_type "text/plain; version=0.0.4";
  map $arg_watch $response_kind { default list; true watch; }
  map $arg_labelSelector $cilium_selector {
    default 0;
    ~^k8s-app(?:=|%3[Dd])cilium$ 1;
  }
  server {
    listen 8080;
    root /fixtures;
    default_type application/json;
    # Deliver initial events immediately, then whitespace slowly enough to
    # keep the watch open throughout both scrape states.
    limit_rate_after 16384;
    limit_rate 1024;
    location = /api/v1/namespaces/kube-system/pods {
      if ($cilium_selector = 0) { return 400; }
      try_files /pods-$response_kind.json =404;
    }
    location = /api/v1/services { try_files /services-$response_kind.json =404; }
    location / { return 404; }
  }
  server { listen 9965; location = /metrics { alias /fixtures/node-a.metrics; } }
  server { listen 9966; location = /metrics { alias /fixtures/node-b.metrics; } }
  server { listen 9962; location = /metrics { return 200 "fixture_control_total 1\n"; } }
}
NGINX
for node in a b; do
  value=7
  [[ "${node}" != b ]] || value=19
  cat > "${temporary}/node-${node}.metrics" <<METRICS
# TYPE hubble_drop_total counter
hubble_drop_total{protocol="TCP",reason="POLICY_DENIED",source="192.0.2.1",destination="example/cache"} ${value}
hubble_flows_processed_total 101
hubble_tcp_flags_total 102
hubble_dns_queries_total 103
hubble_http_requests_total 104
METRICS
done
printf 'scrape_configs: []\n' > "${temporary}/prometheus.yml"
chmod 755 "${temporary}"

for dependency in "${image}" nginx:1.28-alpine prom/prometheus:v3.5.0; do
  if ! "${docker}" image inspect "${dependency}" >/dev/null 2>&1; then
    "${docker}" pull "${dependency}"
  fi
done
# No collector can reach the cluster, Cloud telemetry, or the public Internet.
"${docker}" network create --internal "${network}" >/dev/null
"${docker}" run -d --rm --name "${fixture}" --network "${network}" \
  --network-alias fixture --network-alias hubble-metrics.kube-system.svc \
  --network-alias hubble-metrics.example.svc \
  -v "${temporary}:/fixtures:ro" --entrypoint nginx nginx:1.28-alpine \
  -c /fixtures/nginx.conf -g 'daemon off;' >/dev/null
address=$("${docker}" inspect "${fixture}" | jq -r --arg network "${network}" '.[0].NetworkSettings.Networks[$network].IPAddress')
jq -n --arg ip "${address}" '
  [ ["agent-a", "node-a", 9965, "Running", "True"],
    ["agent-b", "node-b", 9966, "Running", "False"],
    ["pending", "node-c", 9962, "Pending", "False"] ]
  | map(. as $p | {
      apiVersion: "v1", kind: "Pod",
      metadata: {name: $p[0], namespace: "kube-system", uid: $p[0],
                 resourceVersion: "1", labels: {"k8s-app": "cilium"}},
      spec: {nodeName: $p[1], containers: [{name: "cilium-agent", ports: [
        {name: "prometheus", containerPort: 9962, protocol: "TCP"},
        {name: "hubble-metrics", containerPort: $p[2], protocol: "TCP"}]}]},
      status: {phase: $p[3], podIP: $ip, conditions: [{type: "Ready", status: $p[4]}]}
    })
  | {apiVersion: "v1", kind: "PodList", metadata: {resourceVersion: "1"}, items: .}
' > "${temporary}/pods-list.json"
jq -n '
  [["kube-system", "hubble"], ["example", "control"]]
  | map(. as $s | {
      apiVersion: "v1", kind: "Service",
      metadata: {name: "hubble-metrics", namespace: $s[0], uid: $s[0], resourceVersion: "1",
        annotations: {"prometheus.io/scrape": "true", "prometheus.io/port": "9962"},
        labels: {"app.kubernetes.io/name": $s[1]}},
      spec: {type: "ClusterIP", clusterIP: "None", ports: [{name: "metrics", port: 9962, protocol: "TCP"}]}
    })
  | {apiVersion: "v1", kind: "ServiceList", metadata: {resourceVersion: "1"}, items: .}
' > "${temporary}/services-list.json"
for resource in pods services; do
  jq -c '.items[] | {type: "ADDED", object: .}' "${temporary}/${resource}-list.json" > "${temporary}/${resource}-watch.json"
  jq -cn --arg kind "$(jq -r '.items[0].kind' "${temporary}/${resource}-list.json")" '
    {type: "BOOKMARK", object: {apiVersion: "v1", kind: $kind,
      metadata: {resourceVersion: "1", annotations: {"k8s.io/initial-events-end": "true"}}}}
  ' >> "${temporary}/${resource}-watch.json"
  printf '%65536s' '' >> "${temporary}/${resource}-watch.json"
done
"${docker}" run -d --rm --name "${receiver}" --network "${network}" --network-alias receiver \
  -v "${temporary}/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.5.0 --config.file=/etc/prometheus/prometheus.yml \
  --web.enable-remote-write-receiver >/dev/null
"${docker}" run -d --rm --name "${collector}" --network "${network}" \
  -v "${temporary}/pipeline.alloy:/config.alloy:ro" "${image}" \
  run --disable-reporting --cluster.enabled --storage.path=/tmp/alloy /config.alloy >/dev/null

query() {
  "${docker}" exec "${fixture}" wget -qO- -T 2 \
    "http://receiver:9090/api/v1/query?query=$(printf '%s' "$1" | jq -sRr @uri)" \
    | jq -er 'select(.status == "success") | (.data.result[0].value[1] // "0") | tonumber'
}
queries=(
  'count(up{job="hubble"})'
  'sum(up{job="hubble",node="node-a",instance="node-a",namespace="kube-system",pod="agent-a"})'
  'sum(up{job="hubble",node="node-b",instance="node-b",namespace="kube-system",pod="agent-b"})'
  'count(hubble_drop_total{job="hubble"})'
  'sum(hubble_drop_total{node="node-a",protocol="TCP",reason="POLICY_DENIED",source="192.0.2.1",destination="example/cache"})'
  'sum(hubble_drop_total{node="node-b",protocol="TCP"})'
  'count(scrape_samples_scraped{job="hubble"})'
  'sum(scrape_samples_scraped{job="hubble",node="node-a",instance="node-a",namespace="kube-system",pod="agent-a"})'
  'sum(scrape_samples_scraped{job="hubble",node="node-b",instance="node-b",namespace="kube-system",pod="agent-b"})'
  'count({job="hubble",__name__!~"hubble_drop_total|up|scrape_samples_scraped"})'
  'count(up{job="control"})'
  'sum(up{job="control"})'
)
for failed in false true; do
  expected=(2 1 1 2 7 19 2 5 5 0 1 1)
  if [[ "${failed}" == true ]]; then
    mv "${temporary}/node-b.metrics" "${temporary}/node-b.off"
    expected[2]=0
    expected[3]=1
    expected[5]=0
    expected[8]=0
  fi
  deadline=$((SECONDS + 45))
  stable_since=-1
  while true; do
    matched=true
    actual=()
    for i in "${!queries[@]}"; do
      actual[i]=$(query "${queries[i]}" 2>/dev/null) || matched=false
      [[ "${actual[i]}" == "${expected[i]}" ]] || matched=false
    done
    if [[ "${matched}" == true ]]; then
      if (( stable_since < 0 )); then stable_since=${SECONDS}; fi
      if (( SECONDS - stable_since >= 6 )); then break; fi
    else
      stable_since=-1
    fi
    if (( SECONDS >= deadline )) || [[ $("${docker}" inspect -f '{{.State.Running}}' "${collector}") != true ]]; then
      printf 'Hubble checks failed (failed=%s)\n' "${failed}" >&2
      for i in "${!queries[@]}"; do
        printf '%s: expected=%s actual=%s\n' "${queries[i]}" "${expected[i]}" "${actual[i]}" >&2
      done
      exit 1
    fi
    sleep 0.5
  done
  printf 'Hubble per-node discovery, attribution, health and retention pass: failed=%s\n' "${failed}"
done
