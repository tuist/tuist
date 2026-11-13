#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chart=infra/helm/k8s-monitoring
for environment in staging canary production; do
  helm lint "$chart" -n observability -f "$chart/values-$environment.yaml"
  helm template k8s-monitoring "$chart" -n observability -f "$chart/values-$environment.yaml" > "$tmp/rendered.yaml"
  if grep -q 'Destination: greptimedb-' "$tmp/rendered.yaml"; then exit 1; fi
  # Workload clusters no longer write to the Pulse release, its Secret, or its
  # service-graph collector; Cloud keeps every signal.
  if grep -Eq 'pulse[-_](metrics|logs|traces)|pulse\.observability|pulse-credentials' "$tmp/rendered.yaml"; then exit 1; fi
  for signal in metrics logs traces; do
    grep -q "Destination: grafana-cloud-$signal" "$tmp/rendered.yaml"
  done
  yq -o=json '.' "$chart/values-$environment.yaml" | jq -e '
    .["k8s-monitoring"].destinations | keys | all(startswith("pulse-") | not)
  ' > /dev/null
done
# Management and pentest collect metrics only for Cloud as well.
for environment in management pentest; do
  helm lint "$chart" -n observability -f "$chart/values-$environment.yaml"
  helm template k8s-monitoring "$chart" -n observability -f "$chart/values-$environment.yaml" > "$tmp/rendered.yaml"
  if grep -Eq 'pulse[-_](metrics|logs|traces)|pulse\.observability|pulse-credentials' "$tmp/rendered.yaml"; then exit 1; fi
  grep -q 'Destination: grafana-cloud-metrics' "$tmp/rendered.yaml"
done
echo 'PASS: all collectors write only to Grafana Cloud; no Pulse ingestion remains'
