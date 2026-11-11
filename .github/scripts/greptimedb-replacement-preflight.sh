#!/usr/bin/env bash
# CI-only reads of workload/ESO metadata and desired specs, never Secrets.
set -euo pipefail
rendered=${1:?rendered gateway chart required}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
yq ea -o=json -I=0 '.' "$rendered" | jq -s 'map(select(. != null))' > "$tmp/desired.json"
for resource in deployment/pulse service/pulse ingress/pulse serviceaccount/pulse externalsecret/pulse-credentials; do
  kubectl -n observability get "$resource" -o json | jq -e '
    .metadata.annotations["meta.helm.sh/release-name"] == "pulse" and
    .metadata.annotations["meta.helm.sh/release-namespace"] == "observability" and
    .metadata.labels["app.kubernetes.io/managed-by"] == "Helm"' > /dev/null
done
kubectl -n observability get deployment pulse -o json | jq -e '
  .spec.selector.matchLabels == {"app.kubernetes.io/name":"pulse","app.kubernetes.io/instance":"pulse"} and
  .spec.strategy.type == "Recreate"' > /dev/null
kubectl -n observability get deployments -o json | jq -e '
  all(.items[]; .metadata.annotations["meta.helm.sh/release-name"] != "pulse" or .metadata.name == "pulse")' > /dev/null
kubectl -n observability get service pulse -o json | jq -e '
  .spec.type == "ClusterIP" and .spec.selector == {"app.kubernetes.io/name":"pulse","app.kubernetes.io/instance":"pulse"} and
  any(.spec.ports[]; .name == "http" and .port == 4000 and .targetPort == "http")' > /dev/null
kubectl -n observability get externalsecret pulse-credentials -o json > "$tmp/live-eso.json"
jq -e --slurpfile desired "$tmp/desired.json" '
  ($desired[0][] | select(.kind == "ExternalSecret").spec) as $want |
  .spec.secretStoreRef == $want.secretStoreRef and
  .spec.target.name == $want.target.name and
  .spec.target.creationPolicy == $want.target.creationPolicy and
  .spec.target.template.engineVersion == $want.target.template.engineVersion and
  .spec.target.template.data == $want.target.template.data and
  (.spec.data | sort_by(.secretKey)) == ($want.data | sort_by(.secretKey))
' "$tmp/live-eso.json" > /dev/null
# Refuse collisions on the only newly named resource. Existing backend ownership
# never moves into this release, and no bucket content is listed or deleted here.
kubectl -n observability get configmap pulse-greptimedb-gateway --ignore-not-found -o json | jq -e '
  .metadata.annotations["meta.helm.sh/release-name"] == "pulse" and
  .metadata.annotations["meta.helm.sh/release-namespace"] == "observability"' > /dev/null || {
  # kubectl emits nothing for a missing object; distinguish absence from a conflict.
  name=$(kubectl -n observability get configmap pulse-greptimedb-gateway --ignore-not-found -o name)
  test -z "$name"
}
kubectl get nodes -l node.cluster.x-k8s.io/pool=general -o json > "$tmp/nodes.json"
kubectl get pods -A -o json > "$tmp/pods.json"
node .github/scripts/openobserve-capacity.mjs "$tmp/nodes.json" "$tmp/pods.json" "$tmp/desired.json"
echo 'PASS: existing origin/selectors/ESO owner and contents preserved; gateway capacity qualified'
