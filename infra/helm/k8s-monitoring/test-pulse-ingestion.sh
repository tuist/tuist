#!/usr/bin/env bash
# Render every source path, then exercise the shipped servicegraph connector
# against an isolated Prometheus remote-write receiver. No cloud credentials.
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
docker="${DOCKER:-docker}"
network="pulse-ingestion-$$"
collector="${network}-alloy"
receiver="${network}-receiver"
cleanup() {
  result=$?
  if (( result != 0 )); then
    "${docker}" logs "${collector}" 2>&1 || true
    "${docker}" logs "${receiver}" 2>&1 || true
  fi
  "${docker}" rm -fv "${collector}" "${receiver}" >/dev/null 2>&1 || true
  "${docker}" network rm "${network}" >/dev/null 2>&1 || true
  rm -rf "${temporary}"
}
trap cleanup EXIT

for environment in staging canary production management pentest; do
  helm lint "${directory}" -f "${directory}/values-${environment}.yaml" >/dev/null
  helm template k8s-monitoring "${directory}" -n observability \
    -f "${directory}/values-${environment}.yaml" > "${temporary}/${environment}.yaml"
  yq ea -o=json '[.]' "${temporary}/${environment}.yaml" > "${temporary}/${environment}.json"
  jq -e '
    [.[] | select(.kind == "ConfigMap") | select(.metadata.name | test("alloy-(metrics|control-plane)$"))] |
    length == 2 and all(.[];
      (.data["config.alloy"] | contains("prometheus.remote_write \"pulse_metrics\"")) and
      (.data["config.alloy"] | contains("prometheus.remote_write \"grafana_cloud_metrics\"")))
  ' "${temporary}/${environment}.json" >/dev/null
done

# Exercise the actual workflow bootstrap gate with missing/stale/ready status.
yq -r '.jobs.apply.steps[] | select(.name == "Install management-cluster monitoring") | .run' \
  "${directory}/../../../.github/workflows/mgmt-cluster-apply.yml" |
  awk '/^pulse_args=\(/ { copying=1 } copying && /^helm upgrade/ { exit } copying { print }' \
  > "${temporary}/gate.sh"
test -s "${temporary}/gate.sh"
kubectl() {
  case "$*" in
    *'get deployment pulse'*)
      [[ "$gate_case" != missing ]] || return 1
      jq -nc --argjson observed "$([[ "$gate_case" == stale ]] && echo 1 || echo 2)" \
        '{metadata:{generation:2},spec:{replicas:1},status:{observedGeneration:$observed,
          availableReplicas:1,conditions:[{type:"Available",status:"True"}]}}'
      ;;
    *'get externalsecret pulse-credentials'*)
      jq -nc --arg status "$([[ "$gate_case" == secret_pending ]] && echo False || echo True)" \
        '{status:{conditions:[{type:"Ready",status:$status}]}}'
      ;;
    *) return 1 ;;
  esac
}
for gate_case in missing stale secret_pending ready; do
  source "${temporary}/gate.sh"
  if [[ "$gate_case" == ready ]]; then
    test "${#pulse_args[@]}" -eq 0
  else
    test "${#pulse_args[@]}" -eq 6
  fi
done
gate_case=missing
source "${temporary}/gate.sh"
unset -f kubectl

# Bootstrap fallback emits no Pulse component or credential dependency.
helm template k8s-monitoring "${directory}" -n observability \
  -f "${directory}/values-management.yaml" \
  "${pulse_args[@]}" \
  > "${temporary}/management-bootstrap.yaml"
if rg -q 'pulse_metrics|pulse-credentials' "${temporary}/management-bootstrap.yaml"; then
  echo 'Management bootstrap unexpectedly requires Pulse components or credentials' >&2
  exit 1
fi

for environment in staging canary production; do
  jq -e '
    [.[] | select(.kind == "Alloy" and (.metadata.name | endswith("pulse-traces-servicegraph")))] |
    length == 1 and (.[0].spec.alloy.configMap.content |
      contains("otelcol.exporter.prometheus.pulse_metrics.input") and
      (contains("grafana_cloud") | not))
  ' "${temporary}/${environment}.json" >/dev/null
  # Cloud and Pulse must apply the same policy to Kura identity, temporary
  # rollout markers and non-production filters, not only share input scrapes.
  jq -r '.[] | select(.kind == "ConfigMap" and (.metadata.name | endswith("alloy-metrics"))) |
    .data["config.alloy"]' "${temporary}/${environment}.json" > "${temporary}/metrics.alloy"
  for destination in grafana_cloud_metrics pulse_metrics; do
    awk -v destination="${destination}" '
      $0 == "prometheus.remote_write \"" destination "\" {" { copying=1 }
      copying && /write_relabel_config \{/ { rule=1 }
      rule { print }
      rule && /^    }/ { rule=0 }
      copying && /^}/ { exit }
    ' "${temporary}/metrics.alloy" > "${temporary}/${destination}.rules"
  done
  test -s "${temporary}/pulse_metrics.rules"
  cmp "${temporary}/grafana_cloud_metrics.rules" "${temporary}/pulse_metrics.rules"
done

jq -r '.[] | select(.kind == "Alloy" and (.metadata.name | endswith("pulse-traces-servicegraph"))) |
  .spec.alloy.configMap.content' "${temporary}/production.json" > "${temporary}/graph.alloy"
awk '
  /^otelcol.connector.servicegraph / { copying=1 }
  copying {
    sub(/metrics_flush_interval = "60s"/, "metrics_flush_interval = \"1s\"")
    print
  }
  copying && /^}/ { exit }
' "${temporary}/graph.alloy" > "${temporary}/pipeline.alloy"
# Exercise the rendered staging destination transform, not a copy of its OTTL.
jq -r '.[] | select(.kind == "ConfigMap" and (.metadata.name | endswith("alloy-receiver"))) |
  .data["config.alloy"]' "${temporary}/staging.json" > "${temporary}/receiver.alloy"
awk '
  /^otelcol.processor.transform "pulse_traces"/ { copying=1 }
  copying && /^  output \{/ {
    print "  output { traces = [otelcol.exporter.file.verification.input] }\n}"
    exit
  }
  copying { print }
' "${temporary}/receiver.alloy" >> "${temporary}/pipeline.alloy"
cat >> "${temporary}/pipeline.alloy" <<'ALLOY'
otelcol.receiver.otlp "fixture" {
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces = [otelcol.connector.servicegraph.service_graph_metrics.input, otelcol.processor.transform.pulse_traces.input]
  }
}
otelcol.exporter.file "verification" {
  path = "/tmp/trace-normalization.json"
}
otelcol.exporter.prometheus "pulse_metrics" {
  forward_to = [prometheus.remote_write.pulse_metrics.receiver]
}
prometheus.remote_write "pulse_metrics" {
  endpoint { url = "http://receiver:9090/api/v1/write" }
}
ALLOY
printf 'global:\n  scrape_interval: 1s\nscrape_configs: []\n' > "${temporary}/prometheus.yml"
"${docker}" network create "${network}" >/dev/null
"${docker}" run -d --name "${receiver}" --network "${network}" --network-alias receiver \
  -v "${temporary}/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.5.0 --config.file=/etc/prometheus/prometheus.yml \
  --web.enable-remote-write-receiver >/dev/null
"${docker}" run -d --name "${collector}" --network "${network}" --network-alias collector \
  -v "${temporary}/pipeline.alloy:/config.alloy:ro" grafana/alloy:v1.15.0 \
  run --disable-reporting --stability.level=public-preview --storage.path=/tmp/alloy --server.http.listen-addr=0.0.0.0:12345 /config.alloy >/dev/null
deadline=$((SECONDS + 60))
until "${docker}" exec "${receiver}" wget -qO- http://collector:12345/-/ready >/dev/null 2>&1; do
  (( SECONDS < deadline )) || exit 1
  sleep 0.5
done

# Two asymmetric service pairs distinguish total/failed and client/server roles.
now="$(date +%s)"
for pair in 'backend 1 0' 'payments 2 2'; do
  read -r server id status <<< "${pair}"
  payload="$(jq -nc --arg server "${server}" --arg id "${id}" --argjson status "${status}" --arg now "${now}" '
    {resourceSpans: ([{service:"frontend",kind:3,span:"1111111111111111",parent:""},
                      {service:$server,kind:2,span:"2222222222222222",parent:"1111111111111111"}] |
      map({resource:{attributes:[{key:"service.name",value:{stringValue:.service}}]},
        scopeSpans:[{spans:[{traceId:("0000000000000000000000000000000"+$id),spanId:.span,parentSpanId:.parent,
          name:"request",kind:.kind,startTimeUnixNano:($now+"000000000"),endTimeUnixNano:($now+"015000000"),
          status:{code:$status}}]}]}))}')"
  "${docker}" exec "${receiver}" wget -qO- --header='Content-Type: application/json' \
    --post-data="${payload}" http://collector:4318/v1/traces >/dev/null
done
query() {
  encoded="$(printf '%s' "$1" | jq -sRr @uri)"
  "${docker}" exec "${receiver}" wget -qO- "http://127.0.0.1:9090/api/v1/query?query=${encoded}"
}
deadline=$((SECONDS + 60))
until query 'sum(traces_service_graph_request_total)' | jq -e '.data.result[0].value[1] == "2"' >/dev/null; do
  (( SECONDS < deadline )) || exit 1
  sleep 0.5
done
query 'sum(traces_service_graph_request_total{client="frontend",server="backend"})' |
  jq -e '.data.result[0].value[1] == "1"' >/dev/null
query 'sum(traces_service_graph_request_failed_total{client="frontend",server="payments"})' |
  jq -e '.data.result[0].value[1] == "1"' >/dev/null
query 'sum(traces_service_graph_request_client_seconds_count{client="frontend"})' |
  jq -e '.data.result[0].value[1] == "2"' >/dev/null

# Missing HTTP status must not lose the error span or invent a success code.
# Numeric success/failure codes and unrelated string placeholders are controls.
payload="$(jq -nc --arg now "${now}" '
  {resourceSpans:[{resource:{attributes:[{key:"service.name",value:{stringValue:"tuist-server"}}]},
    scopeSpans:[{scope:{name:"opentelemetry_bandit"},spans:(
      [{name:"missing-status",id:"3",value:{stringValue:"nil"}},
       {name:"success-status",id:"4",value:{intValue:"201"}},
       {name:"error-status",id:"5",value:{intValue:"503"}},
       {name:"absent-status",id:"6",value:null}] | map({
        traceId:"00000000000000000000000000000003",spanId:("000000000000000"+.id),name:.name,
        startTimeUnixNano:($now+"000000000"),endTimeUnixNano:($now+"015000000"),status:{code:2},
        attributes:([{key:"other.attribute",value:{stringValue:"nil"}}] +
          if .value == null then [] else [{key:"http.response.status_code",value:.value}] end)
      }))}]}]}')"
"${docker}" exec "${receiver}" wget -qO- --header='Content-Type: application/json' \
  --post-data="${payload}" http://collector:4318/v1/traces >/dev/null
deadline=$((SECONDS + 30))
until "${docker}" cp "${collector}:/tmp/trace-normalization.json" "${temporary}/traces.json" >/dev/null 2>&1 &&
  jq -se '
    [.[].resourceSpans[].scopeSpans[].spans[] | select(.name | endswith("-status"))] |
    length == 4 and all(.[];
      .status.code == 2 and
      any(.attributes[]; .key == "other.attribute" and .value.stringValue == "nil") and
      ([.attributes[] | select(.key == "http.response.status_code") | .value] ==
        if .name == "success-status" then [{intValue:"201"}]
        elif .name == "error-status" then [{intValue:"503"}]
        else [] end))
  ' "${temporary}/traces.json" >/dev/null; do
  (( SECONDS < deadline )) || exit 1
  sleep 0.5
done
printf 'PASS: missing-status error spans retained; integer HTTP codes and unrelated attributes unchanged\n'
printf 'All five environment paths, management bootstrap fallback, shared metric rules and actual service-graph remote write passed\n'
