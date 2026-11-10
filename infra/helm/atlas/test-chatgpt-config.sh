#!/usr/bin/env bash
# Offline rendering checks; never reads 1Password or contacts a cluster.
set -euo pipefail
for tool in helm yq jq; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done
if ! yq --version | grep -Eq 'mikefarah/yq.*version v4\.'; then
  echo 'ChatGPT rendering checks require mikefarah/yq version 4.' >&2
  exit 1
fi
chart="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

render() {
  local name="$1"
  shift
  helm template atlas "$chart" --namespace atlas-test "$@" |
    yq eval-all -o=json '.' | jq --slurp '.' > "$work/$name.json"
}

render standalone
render demo --values "$chart/values-demo.yaml"
for name in standalone demo; do
  jq --exit-status '
    [ .. | objects | select(has("ATLAS_CHATGPT_CLIENT_ID") or
        .name? == "ATLAS_CHATGPT_CLIENT_ID" or
        .secretKey? == "ATLAS_CHATGPT_CLIENT_ID") ] | length == 0
  ' "$work/$name.json" > /dev/null
done

check_managed() {
  jq --exit-status --arg remote "$2" '
    [ .[] | select(.kind == "ExternalSecret" and .metadata.name == "atlas-app") ] as $secrets |
    ($secrets | length == 1) and
    ($secrets[0].spec.secretStoreRef == {"name": "onepassword", "kind": "ClusterSecretStore"}) and
    ($secrets[0].spec.target.name == "atlas-app") and
    ($secrets[0].spec.target.template.data.ATLAS_CHATGPT_CLIENT_ID == "{{ .ATLAS_CHATGPT_CLIENT_ID | trim }}") and
    ([ $secrets[0].spec.data[] | select(.secretKey == "ATLAS_CHATGPT_CLIENT_ID") | .remoteRef.key ] == [$remote]) and
    ([ .[] | select(.kind == "Deployment") | .spec.template.spec |
        (.containers[]?, .initContainers[]?) | select(.name == "atlas" or .name == "migrate") ] as $containers |
      ($containers | length == 2) and
      all($containers[];
        any(.envFrom[]?; .secretRef.name == "atlas-app") and
        all(.env[]?; .name != "ATLAS_CHATGPT_CLIENT_ID")))
  ' "$1" > /dev/null
}

render managed --values "$chart/values-managed-production.yaml"
check_managed "$work/managed.json" 'atlas-chatgpt-oauth/client_id'
render replacement --values "$chart/values-managed-production.yaml" \
  --set-string externalSecrets.items.ATLAS_CHATGPT_CLIENT_ID.remoteRef=atlas-authorized-oauth/client_id
check_managed "$work/replacement.json" 'atlas-authorized-oauth/client_id'

echo 'Atlas ChatGPT configuration passed: managed Secret sourcing, no env shadowing, standalone/demo isolation.'
