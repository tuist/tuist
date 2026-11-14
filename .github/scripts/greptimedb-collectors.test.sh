#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chart=infra/helm/k8s-monitoring
origin=http://pulse.observability.svc.cluster.local:4000
# Extract one top-level-or-indented Alloy block by its exact opening line.
block() { awk -v start="$1" '$0 ~ "^ *" start " \\{$" { copying=1; indent=match($0, /[^ ]/) } copying { print } copying && $0 ~ "^ {" indent-1 "}}$" { exit }' "$2"; }
for environment in staging canary production; do
  helm lint "$chart" -n observability -f "$chart/values-$environment.yaml"
  helm template k8s-monitoring "$chart" -n observability -f "$chart/values-$environment.yaml" > "$tmp/rendered.yaml"
  # Cloud and Pulse (the GreptimeDB fork) each keep every signal. Nothing reads
  # the legacy pulse-credentials Secret or the retired interim greptimedb release.
  if grep -Eq 'pulse-credentials|greptimedb\.observability|greptimedb-dashboard-auth|greptimedb[_-](metrics|logs|traces)' "$tmp/rendered.yaml"; then exit 1; fi
  for signal in metrics logs traces; do
    grep -q "Destination: grafana-cloud-$signal" "$tmp/rendered.yaml"
    grep -q "Destination: pulse-$signal" "$tmp/rendered.yaml"
  done
  yq ea -o=json '[.]' "$tmp/rendered.yaml" > "$tmp/rendered.json"
  config() { jq -er --arg name "$1" '.[] | select(.kind == "ConfigMap" and (.metadata.name | endswith($name))) | .data["config.alloy"]' "$tmp/rendered.json"; }
  config alloy-metrics > "$tmp/metrics.alloy"
  config alloy-control-plane > "$tmp/control-plane.alloy"
  config alloy-receiver > "$tmp/receiver.alloy"

  # Metrics: native remote write, public database, write-only user, Cloud's policy.
  for file in metrics control-plane; do
    block 'prometheus.remote_write "pulse_metrics"' "$tmp/$file.alloy" > "$tmp/writer.alloy"
    grep -Fq "url = \"$origin/v1/prometheus/write\"" "$tmp/writer.alloy"
    grep -Fq '"X-Greptime-DB-Name" = "public",' "$tmp/writer.alloy"
    grep -Fq 'remote.kubernetes.secret.pulse_metrics.data["ingest-username"]' "$tmp/writer.alloy"
    grep -Fq 'remote.kubernetes.secret.pulse_metrics.data["ingest-password"]' "$tmp/writer.alloy"
    block 'remote.kubernetes.secret "pulse_metrics"' "$tmp/$file.alloy" | grep -Eq 'name += "pulse-dashboard-auth"'
  done
  for destination in grafana_cloud_metrics pulse_metrics; do
    awk -v destination="$destination" '
      $0 == "prometheus.remote_write \"" destination "\" {" { copying=1 }
      copying && /write_relabel_config \{/ { rule=1 }
      rule { print }
      rule && /^    }/ { rule=0 }
      copying && /^}/ { exit }
    ' "$tmp/metrics.alloy" > "$tmp/$destination.rules"
  done
  test -s "$tmp/pulse_metrics.rules"
  cmp "$tmp/grafana_cloud_metrics.rules" "$tmp/pulse_metrics.rules"

  # Logs: custom WAL-backed writer with the Loki pipeline headers and no tenant.
  block 'loki.write "pulse_logs"' "$tmp/receiver.alloy" > "$tmp/logs.alloy"
  grep -Fq "url = \"$origin/v1/loki/api/v1/push\"" "$tmp/logs.alloy"
  grep -Fq '"X-Greptime-DB-Name" = "public",' "$tmp/logs.alloy"
  grep -Fq '"X-Greptime-Pipeline-Name" = "loki_otlp",' "$tmp/logs.alloy"
  grep -Fq '"X-Greptime-Log-Table-Name" = "opentelemetry_logs",' "$tmp/logs.alloy"
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
  grep -Fq '"X-Greptime-DB-Name" = "public",' "$tmp/traces.alloy"
  grep -Fq '"X-Greptime-Pipeline-Name" = "greptime_trace_v1",' "$tmp/traces.alloy"
  grep -Fq '"X-Greptime-Trace-Table-Name" = "opentelemetry_traces",' "$tmp/traces.alloy"
  # The upstream OTLP and Prometheus destinations always read `tenantId` from an
  # external Secret; pulse-dashboard-auth has none, so Alloy sends an empty
  # X-Scope-OrgID (as for Grafana Cloud), which Greptime ignores.
  block 'otelcol.auth.basic "pulse_traces"' "$tmp/receiver.alloy" | grep -Fq 'data["ingest-password"]'
  block 'remote.kubernetes.secret "pulse_traces"' "$tmp/receiver.alloy" | grep -Eq 'name += "pulse-dashboard-auth"'
  jq -e 'all(.[]; .kind != "Alloy" or (.metadata.name | endswith("pulse-traces-sampler") | not))' \
    "$tmp/rendered.json" > /dev/null

  # Service-graph metrics are derived for Pulse only; Tempo makes Cloud's own.
  jq -e '
    [.[] | select(.kind == "Alloy" and (.metadata.name | endswith("pulse-traces-servicegraph")))] |
    length == 1 and (.[0].spec.alloy.configMap.content |
      contains("otelcol.exporter.prometheus.pulse_metrics.input") and
      (contains("grafana_cloud") | not))
  ' "$tmp/rendered.json" > /dev/null
done
# Management and pentest collect metrics only for Cloud: no Pulse writer or Secret.
for environment in management pentest; do
  helm lint "$chart" -n observability -f "$chart/values-$environment.yaml"
  helm template k8s-monitoring "$chart" -n observability -f "$chart/values-$environment.yaml" > "$tmp/rendered.yaml"
  if grep -Eq 'pulse[-_](metrics|logs|traces)|pulse\.observability|pulse-credentials|greptimedb[_-](metrics|logs|traces)|greptimedb\.observability|pulse-dashboard-auth' "$tmp/rendered.yaml"; then exit 1; fi
  grep -q 'Destination: grafana-cloud-metrics' "$tmp/rendered.yaml"
done
echo 'PASS: workload collectors write natively to Pulse (GreptimeDB) with gateway headers and the write-only pulse-dashboard-auth login; management and pentest stay Cloud-only; Cloud preserved'
