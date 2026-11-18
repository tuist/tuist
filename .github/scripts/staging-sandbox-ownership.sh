#!/usr/bin/env bash
# Metadata-only repair for the existing staging macOS sandbox resources.
set -euo pipefail
[[ "${DEPLOY_ENV:-}" == staging ]]
[[ "${MODE:-inspect}" == inspect || "$MODE" == repair ]]
case "${RESOURCE:-all}" in
  all)
    [[ "${MODE:-inspect}" == inspect ]]
    for resource in serviceaccount role rolebinding daemonset-runners daemonset-rack; do
      RESOURCE="$resource" bash "$0"
    done
    exit 0 ;;
  serviceaccount) kind=ServiceAccount; name=tuist-macos-sandboxd ;;
  role) kind=Role; name=tuist-tuist-macos-sandbox-reader ;;
  rolebinding) kind=RoleBinding; name=tuist-tuist-macos-sandbox-reader ;;
  daemonset-runners|daemonset-rack) kind=DaemonSet; name="tuist-macos-sandboxd-${RESOURCE#daemonset-}" ;;
  *) exit 1 ;;
esac
umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
read_identity() {
  if ! kubectl --request-timeout=30s -n tuist-sandboxes get "$kind" "$name" --ignore-not-found -o json > "$1" 2> "$work/error"; then
    echo '::error::Cannot read staging sandbox identity; raw output withheld.'
    exit 1
  fi
}
read_identity "$work/before.json"
if [[ ! -s "$work/before.json" ]]; then
  echo "$kind/$name absent"
  [[ "${MODE:-inspect}" == inspect ]]
  exit $?
fi
jq -e --arg kind "$kind" --arg name "$name" '
  .kind == $kind and .metadata.name == $name and
  .metadata.namespace == "tuist-sandboxes" and
  (.metadata.uid | test("^[a-f0-9-]{36}$")) and
  (.metadata.resourceVersion | test("^[0-9]+$"))
' "$work/before.json" > /dev/null
jq '{kind, name:.metadata.name, uid:.metadata.uid, resource_version:.metadata.resourceVersion,
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
  (if .kind == "ServiceAccount" then .automountServiceAccountToken == false
   elif .kind == "Role" then .rules == [{apiGroups:[""],resources:["pods"],verbs:["get"]}]
   elif .kind == "RoleBinding" then
     .subjects == [{kind:"ServiceAccount",name:"tuist-server",namespace:"tuist-staging"}] and
     .roleRef == {apiGroup:"rbac.authorization.k8s.io",kind:"Role",name:"tuist-tuist-macos-sandbox-reader"}
   else
     .spec.template.spec.serviceAccountName == "tuist-macos-sandboxd" and
     .spec.selector.matchLabels == {"tuist.dev/macos-sandbox-role":"control",
       "tuist.dev/macos-sandbox-fleet":(.metadata.name | sub("^tuist-macos-sandboxd-"; ""))}
   end) and
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
if ! kubectl --request-timeout=30s -n tuist-sandboxes patch "$kind" "$name" \
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
  (del(.metadata,.status) == ($before[0] | del(.metadata,.status)))
' "$work/after.json" > /dev/null
echo "PASS: $kind/$name UID and specification unchanged; Helm ownership reconciled"
