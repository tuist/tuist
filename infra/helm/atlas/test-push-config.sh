#!/usr/bin/env bash
# Offline checks: no 1Password access, private keys or live cluster required.
set -euo pipefail
for tool in helm yq jq; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done
if ! yq --version | grep -Eq 'mikefarah/yq.*version v4\.'; then
  echo 'Push rendering checks require mikefarah/yq version 4.' >&2
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
  jq --exit-status '[.. | objects | keys[] | select(startswith("ATLAS_APNS_"))] | length == 0' \
    "$work/$name.json" >/dev/null
  jq --exit-status '[.. | objects | (.name?, .secretKey?) | strings | select(startswith("ATLAS_APNS_"))] | length == 0' \
    "$work/$name.json" >/dev/null
done
check_managed() {
  jq --exit-status --arg item "$2" '
    [ .[] | select(.kind == "ExternalSecret" and .metadata.name == "atlas-app") ] as $secrets |
    ($secrets | length == 1) and
    ($secrets[0].spec.secretStoreRef == {"name":"onepassword","kind":"ClusterSecretStore"}) and
    ($secrets[0].spec.target.name == "atlas-app") and
    (["TEAM_ID", "KEY_ID", "PRIVATE_KEY", "ENVIRONMENT"] | all(.[];
      . as $suffix |
      ([ $secrets[0].spec.data[] | select(.secretKey == ("ATLAS_APNS_" + $suffix)) | .remoteRef.key ] ==
        [$item + "/" + ($suffix | ascii_downcase)]))) and
    ($secrets[0].spec.target.template.data.ATLAS_APNS_PRIVATE_KEY == "{{ .ATLAS_APNS_PRIVATE_KEY }}") and
    ($secrets[0].spec.target.template.data.ATLAS_APNS_TEAM_ID == "{{ .ATLAS_APNS_TEAM_ID | trim }}") and
    ($secrets[0].spec.target.template.data.ATLAS_APNS_KEY_ID == "{{ .ATLAS_APNS_KEY_ID | trim }}") and
    ($secrets[0].spec.target.template.data.ATLAS_APNS_ENVIRONMENT == "{{ .ATLAS_APNS_ENVIRONMENT | trim }}") and
    ([ .[] | select(.kind == "Deployment") | .spec.template.spec |
      (.containers[]?, .initContainers[]?) | select(.name == "atlas" or .name == "migrate") ] as $containers |
      ($containers | length == 2) and all($containers[];
        any(.envFrom[]?; .secretRef.name == "atlas-app") and
        all(.env[]?; (.name | startswith("ATLAS_APNS_")) | not)))
  ' "$1" >/dev/null
}
render managed --values "$chart/values-managed-production.yaml"
check_managed "$work/managed.json" atlas-apns
render replacement --values "$chart/values-managed-production.yaml" \
  --set-string externalSecrets.items.ATLAS_APNS_TEAM_ID.remoteRef=rotated-apns/team_id \
  --set-string externalSecrets.items.ATLAS_APNS_KEY_ID.remoteRef=rotated-apns/key_id \
  --set-string externalSecrets.items.ATLAS_APNS_PRIVATE_KEY.remoteRef=rotated-apns/private_key \
  --set-string externalSecrets.items.ATLAS_APNS_ENVIRONMENT.remoteRef=rotated-apns/environment
check_managed "$work/replacement.json" rotated-apns
echo 'Atlas push configuration passed: all credentials and scope, verbatim PEM, no env shadowing, standalone/demo isolation.'
