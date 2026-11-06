#!/usr/bin/env bash
# Offline chart contract checks. Requires Helm, yq v4 and jq.
set -euo pipefail
chart="$(dirname "$(realpath "$0")")"
root="$(realpath "$chart/../../..")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Use the deployment workflow's contract, not a test-only copy.
check_contract() {
  jq -e --arg image "ghcr.io/tuist/pulse:$1" --arg host "$host" \
    --arg version "$1" -f "$root/.github/scripts/pulse-render-contract.jq" "$2" >/dev/null
}

helm lint "$chart" -f "$root/pulse/test/fixtures/helm/synthetic-values.yaml"
helm template standalone "$chart" -f "$root/pulse/test/fixtures/helm/synthetic-values.yaml" > "$tmp/standalone.yaml"
yq -o=json -I=0 '.' "$tmp/standalone.yaml" | jq -s 'map(select(. != null))' > "$tmp/standalone.json"

jq -e '
  (map(select(.kind == "ExternalSecret")) | length == 0) and
  (map(select(.kind == "Secret")) | length == 1)
' "$tmp/standalone.json" > /dev/null

for environment in staging canary production; do
  helm lint "$chart" -f "$chart/values-managed-$environment.yaml"
  helm template pulse "$chart" --namespace observability -f "$chart/values-managed-$environment.yaml" \
    --set image.tag=1.39.7 > "$tmp/managed.yaml"
  yq -o=json -I=0 '.' "$tmp/managed.yaml" | jq -s 'map(select(. != null))' > "$tmp/managed.json"
  host="pulse-$environment.tuist.dev"
  if [[ "$environment" == production ]]; then host=pulse.tuist.dev; fi
  jq -e --arg bucket "tuist-pulso-$environment" --arg host "$host" '
  (map(select(.kind == "Secret" or .kind == "HorizontalPodAutoscaler")) | length == 0) and
  (map(select(.kind == "Service")) | length == 1 and .[0].spec.type == "ClusterIP") and
  (map(select(.kind == "Ingress")) | length == 1 and
    .[0].spec.rules == [{host: $host, http: {paths:
      (["/mcp", "/api/v1/write", "/loki/api/v1/push", "/v1/traces"] |
        map({path: ., pathType: "Exact", backend: {service: {name: "pulse", port: {name: "http"}}}}))}}]) and
  (map(select(.kind == "ExternalSecret")) | length == 1 and
    .[0].spec.target.name == "pulse-credentials" and
    .[0].spec.secretStoreRef == {name: "onepassword", kind: "ClusterSecretStore"} and
    .[0].spec.target.template.data.PULSE_TENANT_TOKENS ==
      "{\"tuist\":\"sha256${{ .PULSE_TENANT_TOKENS | trim | sha256sum }}\"}" and
    .[0].spec.target.template.data["pulse-password"] == "{{ .PULSE_TENANT_TOKENS | trim }}" and
    .[0].spec.target.template.data["pulse-username"] == "tuist" and
    .[0].spec.target.template.data.tenantId == "tuist" and
    (.[0].spec.data | map(.remoteRef.key) | sort) ==
      ["PULSE_S3_CREDENTIALS/access_key_id", "PULSE_S3_CREDENTIALS/secret_access_key",
       "PULSE_SECRET_KEY_BASE/password", "PULSE_TOKEN/password"] and
    (.[0].spec.data | map(.secretKey) | sort) ==
      ["PULSE_S3_ACCESS_KEY_ID", "PULSE_S3_SECRET_ACCESS_KEY", "PULSE_TENANT_TOKENS", "SECRET_KEY_BASE"]) and
  (map(select(.kind == "Deployment")) | length == 1 and
    .[0].spec.replicas == 1 and .[0].spec.strategy.type == "Recreate" and
    .[0].spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"] == "general" and
    .[0].spec.template.metadata.annotations["prometheus.io/scrape"] == "true" and
    .[0].spec.template.spec.containers[0].image == "ghcr.io/tuist/pulse:1.39.7" and
    (.[0].spec.template.spec.containers[0].env | map(select(.name == "PULSE_TENANT_TOKENS")) |
      length == 1 and .[0].valueFrom.secretKeyRef.name == "pulse-credentials") and
    (.[0].spec.template.spec.containers[0].env | map(select(.name == "PULSE_S3_BUCKET")) |
      length == 1 and .[0].value == $bucket) and
    (.[0].spec.template.spec.containers[0].env | map(select(.name == "PULSE_WORKLOAD_IDENTITY_JSON")) |
      length == 1 and (.[0].value | fromjson | map(del(.keys))) == [{name: "atlas-production",
        issuer: "https://kubernetes.default.svc.cluster.local", audiences: [$host], max_token_ttl_seconds: 3600,
        bindings: [{subject: "system:serviceaccount:atlas-production:atlas",
          tenant: "tuist", capabilities: ["read"]}]}]))
' "$tmp/managed.json" > /dev/null
  check_contract 1.39.7 "$tmp/managed.json"

  # pulse@1.39.0 exposed only this exact MCP route, without a body-size override.
  jq '
    (.[] | select(.kind == "Deployment") | .spec.template.spec.containers[0].image) = "ghcr.io/tuist/pulse:1.39.0" |
    (.[] | select(.kind == "Ingress") | .spec.rules[0].http.paths) =
      [{path: "/mcp", pathType: "Exact", backend: {service: {name: "pulse", port: {name: "http"}}}}] |
    del(.[] | select(.kind == "Ingress") | .metadata.annotations["nginx.ingress.kubernetes.io/proxy-body-size"])
  ' "$tmp/managed.json" > "$tmp/legacy.json"
  check_contract 1.39.0 "$tmp/legacy.json"

  # A later release must not silently inherit the historical MCP-only exception.
  jq '(.[] | select(.kind == "Deployment") | .spec.template.spec.containers[0].image) = "ghcr.io/tuist/pulse:1.39.7"' \
    "$tmp/legacy.json" > "$tmp/invalid.json"
  if check_contract 1.39.7 "$tmp/invalid.json"; then
    echo "Expected deployment to reject MCP-only ingress after 1.39.0" >&2
    exit 1
  fi

  for mutation in \
    'del(.[] | select(.kind == "Ingress") | .metadata.annotations["nginx.ingress.kubernetes.io/proxy-body-size"])' \
    '(.[] | select(.kind == "Ingress") | .spec.rules[0].http.paths[0].pathType) = "Prefix"'; do
    jq "$mutation" "$tmp/managed.json" > "$tmp/invalid.json"
    if check_contract 1.39.7 "$tmp/invalid.json"; then
      echo "Expected deployment to reject unsafe ingress: $mutation" >&2
      exit 1
    fi
  done
done

for environment in management pentest; do
  helm lint "$chart" -f "$chart/values-managed-$environment.yaml"
  helm template pulse "$chart" --namespace observability -f "$chart/values-managed-$environment.yaml" > "$tmp/private.yaml"
  yq -o=json -I=0 '.' "$tmp/private.yaml" | jq -s 'map(select(. != null))' > "$tmp/private.json"
  jq -e --arg bucket "tuist-pulse-$environment" '
    (map(select(.kind == "Ingress" or .kind == "Secret")) | length == 0) and
    (map(select(.kind == "ExternalSecret")) | length == 1) and
    (map(select(.kind == "Deployment")) | length == 1 and
      (.[0].spec.template.spec.containers[0].env |
        map(select(.name == "PULSE_S3_BUCKET")) | length == 1 and .[0].value == $bucket))
  ' "$tmp/private.json" >/dev/null
done

# The pinned OCI source cannot read Git overlays; its inline values must agree.
yq -o=json '.' "$chart/values-managed-management.yaml" | jq -S . > "$tmp/overlay.json"
yq ea -o=json 'select(.kind == "HelmRelease") | .spec.values' \
  "$root/infra/flux/pulse-management/helm-release.yaml" | jq -S . > "$tmp/flux.json"
cmp "$tmp/overlay.json" "$tmp/flux.json"

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
