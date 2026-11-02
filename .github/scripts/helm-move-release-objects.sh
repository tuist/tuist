#!/usr/bin/env bash
# Hands rendered objects that another release in the same namespace still owns
# to this release, by rewriting Helm's ownership annotations, so a chart can
# take over an object another chart rendered before. Helm refuses to adopt an
# object annotated for another release. The previous owner must already have
# stopped rendering the object and kept it (helm.sh/resource-policy: keep).
# Objects that are absent, already owned by this release, or owned by any other
# release stay untouched. Idempotent.
# Usage: helm-move-release-objects.sh <rendered-json-array> <from-release> <to-release> <namespace>
set -euo pipefail
render="${1:?rendered JSON array required}"
from="${2:?previous release required}"
to="${3:?release required}"
namespace="${4:?namespace required}"

while IFS= read -r object; do
  [[ -n "$object" ]] || continue
  resource="$(jq -r '.resource' <<< "$object")"
  object_namespace="$(jq -r '.namespace' <<< "$object")"
  name="$(jq -r '.name' <<< "$object")"
  live="$(kubectl --request-timeout=30s -n "$object_namespace" get "$resource" "$name" --ignore-not-found -o json)"
  [[ -n "$live" ]] || continue
  owned="$(jq -r --arg from "$from" --arg ns "$namespace" '
    .metadata.annotations["meta.helm.sh/release-name"] == $from and
      .metadata.annotations["meta.helm.sh/release-namespace"] == $ns
  ' <<< "$live")"
  [[ "$owned" == true ]] || continue
  echo "Moving $resource/$name from release $from to $to."
  kubectl --request-timeout=30s -n "$object_namespace" annotate --overwrite "$resource" "$name" \
    "meta.helm.sh/release-name=$to" "meta.helm.sh/release-namespace=$namespace"
  kubectl --request-timeout=30s -n "$object_namespace" label --overwrite "$resource" "$name" app.kubernetes.io/managed-by=Helm
done < <(jq -c --arg ns "$namespace" '
  .[] | select(.metadata.name != null) | {
    resource: "\(.kind).\(.apiVersion | split("/") | if length == 2 then "\(.[1]).\(.[0])" else "\(.[0])." end)",
    namespace: (.metadata.namespace // $ns),
    name: .metadata.name
  }
' "$render")
