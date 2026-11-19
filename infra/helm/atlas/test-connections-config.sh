#!/usr/bin/env bash
# Offline checks: no provider credentials, 1Password access or live cluster required.
set -euo pipefail
for tool in helm yq jq; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done
if ! yq --version | grep -Eq 'mikefarah/yq.*version v4\.'; then
  echo 'Connections rendering checks require mikefarah/yq version 4.' >&2
  exit 1
fi
chart="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
credentials='{
  "GOOGLE_CLIENT_ID": "atlas-google-oauth/username",
  "GOOGLE_CLIENT_SECRET": "atlas-google-oauth/credential",
  "ATLAS_GITHUB_APP_CLIENT_ID": "atlas-github-app/client_id",
  "ATLAS_GITHUB_APP_CLIENT_SECRET": "atlas-github-app/client_secret",
  "ATLAS_SLACK_CLIENT_ID": "atlas-slack-company/client_id",
  "ATLAS_SLACK_CLIENT_SECRET": "atlas-slack-company/client_secret"
}'
render() {
  local name="$1"
  shift
  helm template atlas "$chart" --namespace atlas-test "$@" |
    yq eval-all -o=json '.' | jq --slurp '.' > "$work/$name.json"
}
render standalone
render demo --values "$chart/values-demo.yaml"
for name in standalone demo; do
  jq --exit-status --argjson credentials "$credentials" '
    [ .. | objects | (keys[], .name?, .secretKey?) | strings |
      select(. as $key | $credentials | has($key)) ] | length == 0
  ' "$work/$name.json" >/dev/null
done
render managed --values "$chart/values-managed-production.yaml"
jq --exit-status --argjson credentials "$credentials" '
  [ .[] | select(.kind == "ExternalSecret" and .metadata.name == "atlas-app") ] as $secrets |
  ($secrets | length == 1) and
  ($secrets[0].spec.secretStoreRef == {"name":"onepassword","kind":"ClusterSecretStore"}) and
  ($secrets[0].spec.target.name == "atlas-app") and
  all($credentials | to_entries[];
    .key as $key | .value as $remote |
    ([ $secrets[0].spec.data[] | select(.secretKey == $key) | .remoteRef.key ] == [$remote]) and
    ($secrets[0].spec.target.template.data[$key] == ("{{ ." + $key + " | trim }}"))) and
  ([ .[] | select(.kind == "Deployment") | .spec.template.spec |
    (.containers[]?, .initContainers[]?) | select(.name == "atlas" or .name == "migrate") ] as $containers |
    ($containers | length == 2) and all($containers[];
      any(.envFrom[]?; .secretRef.name == "atlas-app") and
      all(.env[]?; .name as $key | $credentials | has($key) | not)))
' "$work/managed.json" >/dev/null || {
  echo 'Personal connections require all Google, GitHub and Slack OAuth credentials via atlas-app without env shadowing.' >&2
  exit 1
}
echo 'Atlas connections configuration passed: all three OAuth providers, Secret inheritance, standalone/demo isolation.'
