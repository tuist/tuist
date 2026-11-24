#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chart=infra/helm/k8s-monitoring
origin=http://pulse.observability.svc.cluster.local:4000
# Extract one top-level-or-indented Alloy block by its exact opening line.
# Never pipe it into `grep -q`: grep exits at the first match, and under
# pipefail awk's next write then fails the script with SIGPIPE (exit 141).
block() { awk -v start="$1" '$0 ~ "^ *" start " \\{$" { copying=1; indent=match($0, /[^ ]/) } copying { print } copying && $0 ~ "^ {" indent-1 "}}$" { exit }' "$2"; }
config() { jq -er --arg name "$1" '.[] | select(.kind == "ConfigMap" and (.metadata.name | endswith($name))) | .data["config.alloy"]' "$tmp/rendered.json"; }
# Metrics: native remote write, public database, write-only user, cost policy.
check_metrics() {
  yq ea -o=json '[.]' "$tmp/rendered.yaml" > "$tmp/rendered.json"
  config alloy-metrics > "$tmp/metrics.alloy"
  config alloy-control-plane > "$tmp/control-plane.alloy"
  for file in metrics control-plane; do
    block 'prometheus.remote_write "pulse_metrics"' "$tmp/$file.alloy" > "$tmp/writer.alloy"
    grep -Fq "url = \"$origin/v1/prometheus/write\"" "$tmp/writer.alloy"
    grep -Fq '"X-Pulse-DB-Name" = "public",' "$tmp/writer.alloy"
    grep -Fq 'remote.kubernetes.secret.pulse_metrics.data["ingest-username"]' "$tmp/writer.alloy"
    grep -Fq 'remote.kubernetes.secret.pulse_metrics.data["ingest-password"]' "$tmp/writer.alloy"
    block 'remote.kubernetes.secret "pulse_metrics"' "$tmp/$file.alloy" | grep -E 'name += "pulse-dashboard-auth"' > /dev/null
  done
  # The cost-control relabel rules now live on the Pulse writer.
  block 'prometheus.remote_write "pulse_metrics"' "$tmp/metrics.alloy" | grep 'write_relabel_config {' > /dev/null
}
for environment in staging canary production; do
  helm lint "$chart" -n observability -f "$chart/values-$environment.yaml"
  helm template k8s-monitoring "$chart" -n observability -f "$chart/values-$environment.yaml" > "$tmp/rendered.yaml"
  # Pulse keeps every signal and nothing writes to Grafana Cloud. Nothing
  # reads the legacy pulse-credentials Secret.
  if grep -Eq 'pulse-credentials|grafana[-_]cloud|grafana\.net' "$tmp/rendered.yaml"; then exit 1; fi
  for signal in metrics logs traces; do
    grep -q "Destination: pulse-$signal" "$tmp/rendered.yaml"
  done
  check_metrics
  config alloy-receiver > "$tmp/receiver.alloy"

  # Logs: custom WAL-backed writer with the Loki pipeline headers and no tenant.
  block 'loki.write "pulse_logs"' "$tmp/receiver.alloy" > "$tmp/logs.alloy"
  grep -Fq "url = \"$origin/v1/loki/api/v1/push\"" "$tmp/logs.alloy"
  grep -Fq '"X-Pulse-DB-Name" = "public",' "$tmp/logs.alloy"
  grep -Fq '"X-Pulse-Pipeline-Name" = "loki_otlp",' "$tmp/logs.alloy"
  grep -Fq '"X-Pulse-Log-Table-Name" = "opentelemetry_logs",' "$tmp/logs.alloy"
  grep -Fq 'username = convert.nonsensitive(remote.kubernetes.secret.pulse_logs.data["ingest-username"])' "$tmp/logs.alloy"
  grep -Fq 'password = remote.kubernetes.secret.pulse_logs.data["ingest-password"]' "$tmp/logs.alloy"
  grep -Fq 'enabled = true' "$tmp/logs.alloy"
  if grep -q 'tenant_id' "$tmp/logs.alloy"; then exit 1; fi
  block 'remote.kubernetes.secret "pulse_logs"' "$tmp/receiver.alloy" > "$tmp/logs-secret.alloy"
  grep -Fq 'name = "pulse-dashboard-auth"' "$tmp/logs-secret.alloy"
  grep -Fq 'namespace = "observability"' "$tmp/logs-secret.alloy"

  # Traces: unsampled OTLP/HTTP into the trace pipeline and table.
  block 'otelcol.exporter.otlphttp "pulse_traces"' "$tmp/receiver.alloy" > "$tmp/traces.alloy"
  grep -Fq "endpoint = \"$origin/v1/otlp\"" "$tmp/traces.alloy"
  grep -Fq '"X-Pulse-DB-Name" = "public",' "$tmp/traces.alloy"
  grep -Fq '"X-Pulse-Pipeline-Name" = "pulse_trace_v1",' "$tmp/traces.alloy"
  grep -Fq '"X-Pulse-Trace-Table-Name" = "opentelemetry_traces",' "$tmp/traces.alloy"
  # The upstream OTLP and Prometheus destinations always read `tenantId` from an
  # external Secret; pulse-dashboard-auth has none, so Alloy sends an empty
  # X-Scope-OrgID (as for Grafana Cloud), which Pulse ignores.
  block 'otelcol.auth.basic "pulse_traces"' "$tmp/receiver.alloy" | grep -F 'data["ingest-password"]' > /dev/null
  block 'remote.kubernetes.secret "pulse_traces"' "$tmp/receiver.alloy" | grep -E 'name += "pulse-dashboard-auth"' > /dev/null
  # Pulse types the status-code column from its first write, so Bandit's "nil"
  # string would otherwise reject the whole span.
  block 'otelcol.processor.transform "pulse_traces"' "$tmp/receiver.alloy" |
    grep -F '"delete_key(attributes, \"http.response.status_code\") where attributes[\"http.response.status_code\"] == \"nil\""' > /dev/null
  jq -e 'all(.[]; .kind != "Alloy" or (.metadata.name | endswith("pulse-traces-sampler") | not))' \
    "$tmp/rendered.json" > /dev/null

  # Service-graph metrics are derived from the traces and written to Pulse.
  jq -e '
    [.[] | select(.kind == "Alloy" and (.metadata.name | endswith("pulse-traces-servicegraph")))] |
    length == 1 and (.[0].spec.alloy.configMap.content |
      contains("otelcol.exporter.prometheus.pulse_metrics.input"))
  ' "$tmp/rendered.json" > /dev/null
done
# Management collects metrics only, for its own Pulse.
helm lint "$chart" -n observability -f "$chart/values-management.yaml"
helm template k8s-monitoring "$chart" -n observability -f "$chart/values-management.yaml" > "$tmp/rendered.yaml"
if grep -Eq 'pulse[-_](logs|traces)|pulse-credentials|grafana[-_]cloud|grafana\.net' "$tmp/rendered.yaml"; then exit 1; fi
grep -q 'Destination: pulse-metrics' "$tmp/rendered.yaml"
check_metrics
echo 'PASS: collectors write only to Pulse, natively with its headers and the write-only pulse-dashboard-auth login; management writes metrics to its Pulse'
