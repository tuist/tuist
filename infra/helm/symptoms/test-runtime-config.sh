#!/usr/bin/env bash
# Offline deployment contract: telemetry stays in Pulse; IRM is not deployed.
set -euo pipefail
chart="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for environment in staging canary production; do
  helm template symptoms "$chart" --namespace "symptoms-$environment" \
    -f "$chart/values-$environment.yaml" -f "$chart/values-ci.yaml" |
    yq eval-all -o=json '.' | jq --slurp '.' > "$work/render.json"
  jq --exit-status '
    (.[] | select(.kind == "Deployment") | .spec.template.spec.containers[0].env |
      map({key: .name, value: .value}) | from_entries) as $env |
    ($env.SYMPTOMS_PROMETHEUS_URL == "http://pulse.observability.svc.cluster.local:4000/v1/prometheus") and
    ($env.SYMPTOMS_PROMETHEUS_USER == "dashboard") and
    ($env.SYMPTOMS_PAGING_ENABLED == "false") and
    (.[] | select(.kind == "ExternalSecret" and .metadata.name == "symptoms-runtime") |
      ([.spec.data[].remoteRef.key] | sort) ==
        (["SYMPTOMS/secret_key_base", "SYMPTOMS/api_token", "PULSE_TOKEN/password", "PULSE_TOKEN/password"] | sort) and
      .spec.target.template.data.SYMPTOMS_PROMETHEUS_TOKEN == "{{ .pulse_token | trim }}") and
    ([.. | objects | select(has("toFQDNs"))] | length == 0)
  ' "$work/render.json" > /dev/null
  if grep -Eiq 'grafana_cloud|grafana\.net|IRM_WEBHOOK' "$work/render.json"; then
    echo "Unexpected Grafana Cloud or IRM dependency in $environment" >&2
    exit 1
  fi
done
echo 'PASS: all environments read metrics from Pulse without Grafana Cloud or IRM dependencies'
