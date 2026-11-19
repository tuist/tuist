#!/usr/bin/env bash
# Labels rendered objects that already claim this release through Helm's
# annotations but lack its managed-by label, typically after a manual
# `kubectl apply`. Helm refuses to adopt such objects and fails the upgrade.
# Objects without the release annotations stay untouched.
# Usage: helm-adopt-release-objects.sh <rendered-json-array> <release> <namespace>
set -euo pipefail
render="${1:?rendered JSON array required}"
release="${2:?release required}"
namespace="${3:?namespace required}"

groups="$(jq -c --arg ns "$namespace" '
  [.[] | select(.metadata.name != null) | {
    resource: "\(.kind).\(.apiVersion | split("/") | if length == 2 then "\(.[1]).\(.[0])" else "\(.[0])." end)",
    namespace: (.metadata.namespace // $ns),
    name: .metadata.name
  }] | group_by([.resource, .namespace])[] | {resource: .[0].resource, namespace: .[0].namespace, names: (map(.name) | unique)}
' "$render")"

while IFS= read -r group; do
  [[ -n "$group" ]] || continue
  resource="$(jq -r '.resource' <<< "$group")"
  object_namespace="$(jq -r '.namespace' <<< "$group")"
  mapfile -t names < <(jq -r '.names[]' <<< "$group")
  live="$(kubectl --request-timeout=30s -n "$object_namespace" get "$resource" "${names[@]}" --ignore-not-found -o json)"
  [[ -n "$live" ]] || continue
  mapfile -t orphans < <(jq -r --arg release "$release" --arg ns "$namespace" '
    (if .kind == "List" then .items else [.] end)[] |
      select(.metadata.annotations["meta.helm.sh/release-name"] == $release and
        .metadata.annotations["meta.helm.sh/release-namespace"] == $ns and
        .metadata.labels["app.kubernetes.io/managed-by"] != "Helm") |
      .metadata.name
  ' <<< "$live")
  for name in "${orphans[@]}"; do
    echo "Adopting $resource/$name into release $release: adding the missing managed-by label."
    kubectl --request-timeout=30s -n "$object_namespace" label --overwrite "$resource" "$name" app.kubernetes.io/managed-by=Helm
  done
done <<< "$groups"
