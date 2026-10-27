#!/usr/bin/env bash
# Rendering-only regression checks. Never contacts a Kubernetes cluster.
set -euo pipefail
for tool in helm yq jq; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done
if ! yq --version | grep -Eq 'mikefarah/yq.*version v4\.'; then
  echo 'Agent rendering checks require mikefarah/yq version 4, not Python yq.' >&2
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

  jq --exit-status '
    [ .[] | select(.kind == "Deployment" and .metadata.name == "atlas") ] as $web |
    ($web | length == 1) and
    ($web[0].spec.template.spec.automountServiceAccountToken == false) and
    ($web[0].spec.template.spec.serviceAccountName == "atlas") and
    ([ .[] | select(.kind == "ServiceAccount" and .automountServiceAccountToken != false) ] | length == 0) and
    ([ .[] | select(.kind == "Role" or .kind == "RoleBinding" or
                    .kind == "ClusterRole" or .kind == "ClusterRoleBinding") ] | length == 0)
  ' "$work/$name.json" > /dev/null
}

render standalone --set fullnameOverride=atlas
jq --exit-status '
  ([ .[] | select(.kind == "Namespace") ] | length == 0) and
  ([ .[] | select(.kind == "Deployment" and .metadata.name == "atlas") |
      .spec.template.spec.volumes[]? |
      .projected.sources[]? | select(has("serviceAccountToken")) ] | length == 0)
' "$work/standalone.json" > /dev/null

render managed --values "$chart/values-managed-production.yaml"
jq --exit-status '
  ([ .[] | select(.kind == "Namespace" and .metadata.name == "atlas-agents" and
                  .metadata.annotations["helm.sh/resource-policy"] == "keep") ] | length == 1) and
  ([ .[] | select(.kind == "ServiceAccount" and .metadata.name == "condukt-agent" and
                  .metadata.namespace == "atlas-agents") ] | length == 1) and
  ([ .[] | select(.kind == "Deployment" and .metadata.name == "atlas") |
      .spec.template.spec.volumes[]? | .projected.sources[]? |
      select(has("serviceAccountToken")) | .serviceAccountToken.audience ] == ["tuist-server"]) and
  ([ .[] | select(.kind == "Deployment" and .metadata.name == "atlas") |
      .spec.template.spec.containers[] | .env[] |
      select(.name == "TUIST_SERVER_TOKEN_PATH") | .value ] == ["/var/run/secrets/tuist/token"]) and
  ([ .[] | select(.kind == "Deployment" and .metadata.name == "atlas") |
      .spec.template.spec.containers[] | select(.name == "atlas") | .volumeMounts[]? |
      select(.name == "tuist-server-token") ] ==
    [{"name": "tuist-server-token", "mountPath": "/var/run/secrets/tuist", "readOnly": true}]) and
  ([ .[] | select(.kind == "Deployment" and .metadata.name == "atlas") |
      .spec.template.spec.volumes[]? | select(.name == "tuist-server-token") |
      .projected.sources[]? | .serviceAccountToken ] ==
    [{"path": "token", "audience": "tuist-server", "expirationSeconds": 3600}])
' "$work/managed.json" > /dev/null

# Old operator values cannot restore API access. This next check proves only
# rendering, not live deletion safety; managed upgrades have a separate guard.
render legacy --set fullnameOverride=atlas --set agentSandboxes.enabled=true \
  --set agentSandboxes.namespace=legacy-agents --set agentSandboxes.serviceAccountName=legacy-agent
jq --exit-status '
  [ .[] | select(.kind == "Namespace" and .metadata.name == "legacy-agents" and
                  .metadata.annotations["helm.sh/resource-policy"] == "keep") ] | length == 1
' "$work/legacy.json" > /dev/null
render retired --values "$chart/values-managed-production.yaml" --set agentSandboxes.enabled=false
jq --exit-status '[ .[] | select(.kind == "Namespace") ] | length == 0' \
  "$work/retired.json" > /dev/null

echo 'Atlas web agent boundary passed: no API token automount or sandbox permissions; Tuist identity preserved.'
