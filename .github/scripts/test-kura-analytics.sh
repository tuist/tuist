#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
chart=infra/helm/tuist
rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT

analytics='select(.kind == "ExternalSecret" and .metadata.name == "kura-analytics")'
server='select(.kind == "ExternalSecret" and .metadata.name == "tuist-tuist-server-config-external-secrets")'

check_managed() {
  local environment=$1
  shift
  helm template tuist "$chart" --namespace tuist \
    -f "$chart/values-managed-common.yaml" \
    -f "$chart/values-managed-$environment.yaml" \
    -f "$chart/values-ci.yaml" "$@" > "$rendered"

  yq -e "$analytics | .metadata.namespace == \"kura\" and .spec.target.name == \"kura-shared-secrets\" and .spec.target.creationPolicy == \"Merge\"" "$rendered" > /dev/null
  test "$(yq -r "$analytics | .spec.target.template.data.KURA_ANALYTICS_SERVER_URL" "$rendered")" = \
    'http://tuist-tuist-server.tuist.svc.cluster.local:80'
  test "$(yq -r "$analytics | .spec.target.template.data.KURA_ANALYTICS_SIGNING_KEY" "$rendered")" = \
    '{{ .cache_api_key | trim }}'
  test "$(yq -r "$analytics | .spec.data[] | select(.secretKey == \"cache_api_key\") | .remoteRef.key" "$rendered")" = \
    "$(yq -r "$server | .spec.data[] | select(.secretKey == \"TUIST_CACHE_API_KEY\") | .remoteRef.key" "$rendered")"
  test "$(yq -o=json -I=0 "$analytics | .spec.secretStoreRef" "$rendered")" = \
    "$(yq -o=json -I=0 "$server | .spec.secretStoreRef" "$rendered")"
  test "$(yq -r "$analytics | .spec.refreshInterval" "$rendered")" = \
    "$(yq -r "$server | .spec.refreshInterval" "$rendered")"
  echo "Analytics wiring matches the $environment server."
}

for environment in staging canary production; do
  check_managed "$environment"
done
check_managed production --set server.config.externalSecrets.storeRef.name=custom-store \
  --set server.config.externalSecrets.refreshInterval=15m

helm template custom "$chart" --namespace custom-namespace \
  -f "$chart/values-managed-common.yaml" \
  -f "$chart/values-managed-production.yaml" \
  -f "$chart/values-ci.yaml" --set server.service.port=8081 > "$rendered"
test "$(yq -r "$analytics | .spec.target.template.data.KURA_ANALYTICS_SERVER_URL" "$rendered")" = \
  'http://custom-tuist-server.custom-namespace.svc.cluster.local:8081'

for configuration in self-hosted-ci preview pentest; do
  extra_values=(-f "$chart/values-$configuration.yaml")
  if [ "$configuration" = preview ]; then
    extra_values+=(-f "$chart/values-preview-kura.yaml" -f "$chart/values-preview-ci.yaml")
  fi
  helm template tuist "$chart" "${extra_values[@]}" \
    -f "$chart/values-ci.yaml" > "$rendered"
  if yq -e "$analytics" "$rendered" > /dev/null 2>&1; then
    echo "Unexpected managed analytics in $configuration." >&2
    exit 1
  fi
done

for setting in server.enabled server.config.managedSecrets kuraController.sharedSecrets.enabled; do
  if helm template tuist "$chart" \
    -f "$chart/values-managed-common.yaml" \
    -f "$chart/values-managed-production.yaml" \
    -f "$chart/values-ci.yaml" --set "$setting=false" > "$rendered" 2>&1; then
    echo "Expected analytics configuration to reject $setting=false." >&2
    exit 1
  fi
  grep -q 'kuraController.analytics.enabled requires' "$rendered"
done

echo "Kura analytics configuration checks passed."
