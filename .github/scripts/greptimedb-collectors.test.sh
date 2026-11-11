#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chart=infra/helm/k8s-monitoring
for environment in staging canary production; do
  helm lint "$chart" -n observability -f "$chart/values-$environment.yaml"
  helm template k8s-monitoring "$chart" -n observability -f "$chart/values-$environment.yaml" > "$tmp/rendered.yaml"
  if grep -q 'Destination: greptimedb-' "$tmp/rendered.yaml"; then exit 1; fi
  for signal in metrics logs traces; do
    grep -q "Destination: pulse-$signal" "$tmp/rendered.yaml"
    grep -q "Destination: grafana-cloud-$signal" "$tmp/rendered.yaml"
  done
  yq -o=json '.' "$chart/values-$environment.yaml" | jq -e '
    .["k8s-monitoring"].destinations as $d |
    $d["pulse-metrics"].url == "http://pulse.observability.svc.cluster.local:4000/api/v1/write" and
    $d["pulse-traces"].url == "http://pulse.observability.svc.cluster.local:4000" and
    all($d | to_entries[] | select(.key == "pulse-metrics" or .key == "pulse-traces");
      .value.auth.usernameKey == "pulse-username" and .value.auth.passwordKey == "pulse-password" and
      .value.secret.name == "pulse-credentials")
  ' > /dev/null

  # Logs use a custom destination for WAL isolation. Verify the emitted writer
  # and Secret reference rather than the built-in destination's values shape.
  yq ea -o=json '[.]' "$tmp/rendered.yaml" | jq -er '
    .[] | select(.kind == "ConfigMap" and (.metadata.name | endswith("alloy-receiver"))) |
    .data["config.alloy"]
  ' > "$tmp/receiver.alloy"
  sed -n '/^loki.write "pulse_logs" {/,/^}/p' "$tmp/receiver.alloy" > "$tmp/pulse-logs.alloy"
  grep -Fq 'url = "http://pulse.observability.svc.cluster.local:4000/loki/api/v1/push"' "$tmp/pulse-logs.alloy"
  grep -Fq 'tenant_id = convert.nonsensitive(remote.kubernetes.secret.pulse_logs.data["tenantId"])' "$tmp/pulse-logs.alloy"
  grep -Fq 'username = convert.nonsensitive(remote.kubernetes.secret.pulse_logs.data["pulse-username"])' "$tmp/pulse-logs.alloy"
  grep -Fq 'password = remote.kubernetes.secret.pulse_logs.data["pulse-password"]' "$tmp/pulse-logs.alloy"
  sed -n '/^remote.kubernetes.secret "pulse_logs" {/,/^}/p' "$tmp/receiver.alloy" > "$tmp/pulse-secret.alloy"
  grep -Fq 'name = "pulse-credentials"' "$tmp/pulse-secret.alloy"
  grep -Fq 'namespace = "observability"' "$tmp/pulse-secret.alloy"
done
echo 'PASS: stable Pulse ingestion origins and credentials; independent Cloud destinations preserved'
