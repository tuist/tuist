#!/usr/bin/env bash
# Offline chart contract checks. Requires Helm, yq v4 and jq.
set -euo pipefail
chart="$(dirname "$(realpath "$0")")"
root="$(realpath "$chart/../../..")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

helm lint "$chart" -f "$root/pulse/test/fixtures/helm/synthetic-values.yaml"
helm template standalone "$chart" -f "$root/pulse/test/fixtures/helm/synthetic-values.yaml" > "$tmp/standalone.yaml"
helm lint "$chart" -f "$chart/values-managed-production.yaml"
helm template pulse "$chart" --namespace pulse -f "$chart/values-managed-production.yaml" --set image.tag=1.39.7 > "$tmp/managed.yaml"
for mode in standalone managed; do
  yq -o=json -I=0 '.' "$tmp/$mode.yaml" | jq -s 'map(select(. != null))' > "$tmp/$mode.json"
done

jq -e '
  (map(select(.kind == "ExternalSecret")) | length == 0) and
  (map(select(.kind == "Secret")) | length == 1)
' "$tmp/standalone.json" > /dev/null

jq -e '
  (map(select(.kind == "Secret" or .kind == "Ingress" or .kind == "HorizontalPodAutoscaler")) | length == 0) and
  (map(select(.kind == "Service")) | length == 1 and .[0].spec.type == "ClusterIP") and
  (map(select(.kind == "ExternalSecret")) | length == 1 and
    .[0].spec.target.name == "pulse-app" and
    .[0].spec.secretStoreRef == {name: "onepassword", kind: "ClusterSecretStore"} and
    (.[0].spec.data | map(.secretKey) | sort) ==
      ["PULSE_S3_ACCESS_KEY_ID", "PULSE_S3_SECRET_ACCESS_KEY", "PULSE_TENANT_TOKENS", "SECRET_KEY_BASE"]) and
  (map(select(.kind == "Deployment")) | length == 1 and
    .[0].spec.replicas == 1 and .[0].spec.strategy.type == "Recreate" and
    .[0].spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "general" and
    .[0].spec.template.metadata.annotations["prometheus.io/scrape"] == "true" and
    .[0].spec.template.spec.containers[0].image == "ghcr.io/tuist/pulse:1.39.7" and
    (.[0].spec.template.spec.containers[0].env | map(select(.name == "PULSE_TENANT_TOKENS")) |
      length == 1 and .[0].valueFrom.secretKeyRef.name == "pulse-app"))
' "$tmp/managed.json" > /dev/null

# Invalid managed configurations must fail instead of falling back to generated secrets.
for setting in 'existingSecret=' 'externalSecrets.items=null'; do
  if helm template pulse "$chart" -f "$chart/values-managed-production.yaml" --set "$setting" > "$tmp/invalid.log" 2>&1; then
    echo "Expected Helm to reject $setting" >&2
    exit 1
  fi
done

helm package "$chart" --destination "$tmp" > /dev/null
tar -tzf "$tmp"/pulse-*.tgz > "$tmp/contents"
if grep -E '/(values-managed-[^/]*|test-[^/]*\.sh|AGENTS\.md)$' "$tmp/contents"; then
  echo 'Managed-only files leaked into the published chart' >&2
  exit 1
fi
echo 'Pulse standalone and managed chart contracts passed'
