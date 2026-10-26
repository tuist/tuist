#!/usr/bin/env bash
set -euo pipefail

: "${EXPECTED_STAGING_IMAGE:?The currently deployed provider image is required}"
: "${GITHUB_SHA:?The tested build commit is required}"
namespace=tuist-staging
deployment=tuist-tuist-capi-scaleway-applesilicon
config=tuist-tuist-ovh-runner-egress
image="ghcr.io/tuist/capi-provider-scaleway-applesilicon:${GITHUB_SHA:0:8}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

kubectl --request-timeout=10s get --raw /version >/dev/null
kubectl -n "$namespace" get deployment "$deployment" -o json > "$temporary/before.json"
jq -e --arg expected "$EXPECTED_STAGING_IMAGE" '
  [.spec.template.spec.containers[] | select(.name == "manager")] as $managers |
  ($managers | length) == 1 and $managers[0].image == $expected
' "$temporary/before.json" >/dev/null
kubectl -n "$namespace" get configmap tuist-tuist-ovh-private-network -o json |
  jq -e '.data.vrackID == "pn-2023588" and .data.cidr == "172.30.241.0/24"' >/dev/null

# Do not overwrite an enabled configuration or retained cleanup intent.
kubectl -n "$namespace" get configmap "$config" --ignore-not-found -o json > "$temporary/config.json"
if [ -s "$temporary/config.json" ]; then
  jq -e '.data.enabled == "false"' "$temporary/config.json" >/dev/null
fi
kubectl -n "$namespace" get configmap "$config-reservations" --ignore-not-found -o json > "$temporary/reservations.json"
if [ -s "$temporary/reservations.json" ]; then
  jq -e '(.data["reservations.json"] | fromjson | .machines | length) == 0' "$temporary/reservations.json" >/dev/null
fi

# Render only the feature's ConfigMap/RBAC. This deliberately does not upgrade
# the umbrella release, whose staging application/cache state may be newer.
mkdir -p "$temporary/chart/templates"
printf 'apiVersion: v2\nname: tuist\nversion: 0.0.0\n' > "$temporary/chart/Chart.yaml"
cp infra/helm/tuist/values.yaml "$temporary/chart/values.yaml"
cp infra/helm/tuist/templates/{_helpers.tpl,ovh-runner-egress.yaml} "$temporary/chart/templates/"
helm template tuist "$temporary/chart" --namespace "$namespace" \
  -f infra/helm/tuist/values-managed-common.yaml \
  -f infra/helm/tuist/values-managed-staging.yaml \
  --set capi.ovhRunnerEgress.enabled=false > "$temporary/resources.yaml"
kubectl apply -f "$temporary/resources.yaml"
kubectl annotate -f "$temporary/resources.yaml" --overwrite \
  meta.helm.sh/release-name=tuist meta.helm.sh/release-namespace="$namespace"

# Test the resource version and preserve every existing manager argument.
jq --arg image "$image" --arg flag "--ovh-runner-egress-config=$config" '
  (.spec.template.spec.containers | map(.name) | index("manager")) as $i |
  [
    {op:"test", path:"/metadata/resourceVersion", value:.metadata.resourceVersion},
    {op:"replace", path:("/spec/template/spec/containers/" + ($i|tostring) + "/image"), value:$image},
    {op:"replace", path:("/spec/template/spec/containers/" + ($i|tostring) + "/args"),
     value:([.spec.template.spec.containers[$i].args[] | select(startswith("--ovh-runner-egress-config=") | not)] + [$flag])}
  ]
' "$temporary/before.json" > "$temporary/patch.json"
kubectl -n "$namespace" patch deployment "$deployment" --type=json --patch-file "$temporary/patch.json"
kubectl -n "$namespace" rollout status deployment/"$deployment" --timeout=5m
kubectl -n "$namespace" get ovhdedicatedmachines -o wide
kubectl get ciliumegressgatewaypolicies -o wide
printf 'Provider %s deployed with runner egress disabled.\n' "$image"
