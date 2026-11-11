#!/usr/bin/env bash
# Metadata-only repair for the manually bootstrapped staging sandbox identity.
set -euo pipefail
[[ "${DEPLOY_ENV:-}" == staging ]]
[[ "${MODE:-inspect}" == inspect || "$MODE" == repair ]]
umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
read_identity() {
  if ! kubectl --request-timeout=30s -n tuist-sandboxes get serviceaccount tuist-macos-sandboxd -o json > "$1" 2> "$work/error"; then
    echo '::error::Cannot read staging sandbox identity; raw output withheld.'
    exit 1
  fi
}
read_identity "$work/before.json"
jq -e '
  .kind == "ServiceAccount" and .metadata.name == "tuist-macos-sandboxd" and
  .metadata.namespace == "tuist-sandboxes" and
  (.metadata.uid | test("^[a-f0-9-]{36}$")) and
  (.metadata.resourceVersion | test("^[0-9]+$"))
' "$work/before.json" > /dev/null
jq '{uid:.metadata.uid, resource_version:.metadata.resourceVersion,
  has_controller:((.metadata.ownerReferences // []) | length > 0),
  manually_applied:any(.metadata.managedFields[]?; .manager == "kubectl-client-side-apply"),
  has_release_owner:(.metadata.annotations["meta.helm.sh/release-name"] != null),
  target_release:(.metadata.annotations["meta.helm.sh/release-name"] == "tuist" and
    .metadata.annotations["meta.helm.sh/release-namespace"] == "tuist-staging"),
  helm_managed:(.metadata.labels["app.kubernetes.io/managed-by"] == "Helm"),
  token_automount_disabled:(.automountServiceAccountToken == false)}' "$work/before.json"
[[ "${MODE:-inspect}" == repair ]] || exit 0
# Refuse another controller/release, unexpected token policy, and a recreated
# identity. The exact UID must come from a preceding read-only inspection.
jq -e --arg uid "${EXPECTED_UID:-}" '
  .metadata.uid == $uid and (.metadata.ownerReferences // [] | length == 0) and
  .automountServiceAccountToken == false and
  ((.metadata.labels["app.kubernetes.io/managed-by"] // "Helm") == "Helm") and
  ((.metadata.annotations["meta.helm.sh/release-name"] // "tuist") == "tuist") and
  ((.metadata.annotations["meta.helm.sh/release-namespace"] // "tuist-staging") == "tuist-staging")
' "$work/before.json" > /dev/null
jq '[
  {op:"test",path:"/metadata/uid",value:.metadata.uid},
  {op:"test",path:"/metadata/resourceVersion",value:.metadata.resourceVersion},
  {op:"add",path:"/metadata/labels",value:((.metadata.labels // {}) + {"app.kubernetes.io/managed-by":"Helm"})},
  {op:"add",path:"/metadata/annotations",value:((.metadata.annotations // {}) + {
    "meta.helm.sh/release-name":"tuist","meta.helm.sh/release-namespace":"tuist-staging"})}
]' "$work/before.json" > "$work/patch.json"
if ! kubectl --request-timeout=30s -n tuist-sandboxes patch serviceaccount tuist-macos-sandboxd \
    --type=json --patch-file "$work/patch.json" > "$work/result" 2> "$work/error"; then
  echo '::error::Sandbox ownership repair failed; inspect current state before retrying. Raw output withheld.'
  exit 1
fi
read_identity "$work/after.json"
jq -e --slurpfile before "$work/before.json" '
  .metadata.uid == $before[0].metadata.uid and
  .metadata.labels["app.kubernetes.io/managed-by"] == "Helm" and
  .metadata.annotations["meta.helm.sh/release-name"] == "tuist" and
  .metadata.annotations["meta.helm.sh/release-namespace"] == "tuist-staging" and
  (del(.metadata) == ($before[0] | del(.metadata)))
' "$work/after.json" > /dev/null
echo 'PASS: staging sandbox UID and non-metadata fields unchanged; Helm ownership reconciled'
