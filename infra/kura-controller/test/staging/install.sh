#!/usr/bin/env bash
set -euo pipefail
tag="${1:?controller image tag required}"
[[ "$tag" =~ ^sha-[a-f0-9]{12}$ ]]
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Add only the new fields, preserving independently deployed CRD extensions.
kubectl create --dry-run=client --validate=false -f infra/helm/tuist/crds/kura.tuist.dev_kurainstances.yaml -o json > "$scratch/crd.json"
jq '[.spec.versions[0].schema.openAPIV3Schema.properties as $p |
  ($p.spec.properties | to_entries[] | select(.key == "servingMode" or .key == "primaryPromotion" or .key == "plannedHandover" or .key == "replicaRecovery") |
    {op:"add",path:("/spec/versions/0/schema/openAPIV3Schema/properties/spec/properties/" + .key),value:.value}),
  {op:"add",path:"/spec/versions/0/schema/openAPIV3Schema/properties/status/properties/replicaRecovery",value:$p.status.properties.replicaRecovery}]' "$scratch/crd.json" > "$scratch/patch.json"
kubectl patch crd kurainstances.kura.tuist.dev --type=json --patch-file "$scratch/patch.json"

helm template spec98 infra/helm/tuist --namespace kura-spec98 \
  --set server.enabled=false --set server.migrations.enabled=false --set server.image.tag=unused \
  --show-only templates/kura-controller.yaml \
  --set kuraController.enabled=true --set kuraController.namespace=kura-spec98 \
  --set kuraController.replicaCount=1 --set kuraController.image.tag="$tag" \
  --set kuraController.servingAuthority.enabled=true \
  --set kuraController.telemetry.deploymentEnvironment=staging > "$scratch/controller.yaml"
kubectl apply -f "$scratch/controller.yaml"
kubectl -n kura-spec98 rollout status deployment/spec98-tuist-kura-controller --timeout=180s
