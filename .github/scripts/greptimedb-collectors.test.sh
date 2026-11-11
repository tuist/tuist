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
    $d["pulse-logs"].url == "http://pulse.observability.svc.cluster.local:4000/loki/api/v1/push" and
    $d["pulse-traces"].url == "http://pulse.observability.svc.cluster.local:4000" and
    all($d | to_entries[] | select(.key | startswith("pulse-"));
      .value.auth.usernameKey == "pulse-username" and .value.auth.passwordKey == "pulse-password" and
      .value.secret.name == "pulse-credentials")
  ' > /dev/null
done
echo 'PASS: stable Pulse ingestion origins and credentials; independent Cloud destinations preserved'
