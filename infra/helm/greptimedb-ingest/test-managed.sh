#!/usr/bin/env bash
set -euo pipefail
chart=$(dirname "${BASH_SOURCE[0]}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for environment in staging canary production; do
  helm lint "$chart" -n observability --set "environment=$environment"
  helm template pulse "$chart" -n observability --set "environment=$environment" > "$tmp/gateway.yaml"
  yq ea -o=json -I=0 '.' "$tmp/gateway.yaml" | jq -s 'map(select(. != null))' > "$tmp/gateway.json"
  host="pulse-$environment.tuist.dev"
  if [[ "$environment" == production ]]; then host=pulse.tuist.dev; fi
  jq -e --arg host "$host" '
    length == 6 and all(.[]; .kind != "Secret" and .kind != "PersistentVolumeClaim" and .kind != "StatefulSet") and
    any(.[]; .kind == "Deployment" and .metadata.name == "pulse" and
      .metadata.labels["app.kubernetes.io/name"] == "greptimedb-ingest" and
      .spec.selector.matchLabels == {"app.kubernetes.io/name":"pulse","app.kubernetes.io/instance":"pulse"} and
      .spec.template.metadata.labels == .spec.selector.matchLabels and .spec.strategy.type == "Recreate" and
      (.spec.template.spec.containers | length) == 1 and
      .spec.template.spec.containers[0].image == "nginxinc/nginx-unprivileged:1.28.0-alpine" and
      .spec.template.spec.containers[0].ports[0].containerPort == 4000 and
      (.spec.template.spec | has("volumes")) and (.spec.template.spec.containers[0] | has("envFrom") | not)) and
    any(.[]; .kind == "Service" and .metadata.name == "pulse" and .spec.type == "ClusterIP" and
      .spec.ports == [{name:"http",port:4000,targetPort:"http",protocol:"TCP"}]) and
    any(.[]; .kind == "Ingress" and .metadata.name == "pulse" and .spec.rules[0].host == $host and
      .spec.tls == [{secretName:"pulse-tls",hosts:[$host]}] and
      ([.spec.rules[0].http.paths[].path] | sort) == ["/api/v1/write","/loki/api/v1/push","/v1/traces"] and
      all(.spec.rules[0].http.paths[]; .pathType == "Exact"))
  ' "$tmp/gateway.json" > /dev/null
  # Exact old ESO expressions and provider references; no actual Secret is read.
  helm template pulse infra/helm/pulse -n observability -f "infra/helm/pulse/values-managed-$environment.yaml" > "$tmp/old.yaml"
  yq -o=json 'select(.kind == "ExternalSecret") | .spec' "$tmp/old.yaml" > "$tmp/old-eso.json"
  jq '[.[] | select(.kind == "ExternalSecret").spec][0]' "$tmp/gateway.json" > "$tmp/new-eso.json"
  jq -e --slurpfile old "$tmp/old-eso.json" '
    .target == $old[0].target and .secretStoreRef == $old[0].secretStoreRef and
    .refreshInterval == $old[0].refreshInterval and
    (.data | sort_by(.secretKey)) == ($old[0].data | sort_by(.secretKey))
  ' "$tmp/new-eso.json" > /dev/null
done
if helm template pulse "$chart" -n default > /dev/null 2>&1; then exit 1; fi
if helm template pulse "$chart" -n observability --set environment=other > /dev/null 2>&1; then exit 1; fi
echo 'PASS: existing pulse origin/selector/ESO preserved; ingest-only gateway; backend ownership isolated'
