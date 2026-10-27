#!/usr/bin/env bash
#MISE description="Run the deployed etcd snapshot job on every Ready management control-plane node; optionally remove the superseded static Talos credential after all uploads succeed"
#USAGE flag "--delete-legacy-credential" help="Delete mgmt-system/talos-snapshotter-config only after every node uploads a snapshot successfully"
set -euo pipefail

delete_legacy=false
case "${1:-}" in
  "") ;;
  --delete-legacy-credential) delete_legacy=true ;;
  *) echo "usage: $0 [--delete-legacy-credential]" >&2; exit 1 ;;
esac

namespace=mgmt-system
cronjob=$(kubectl -n "$namespace" get cronjob etcd-snapshot -o json)
jq -e '
  .spec.jobTemplate.spec.template.spec |
  (.hostNetwork // false | not) and
  any(.volumes[]; .secret.secretName == "etcd-snapshot") and
  all(.volumes[]; .secret.secretName != "talos-snapshotter-config")
' <<<"$cronjob" >/dev/null || {
  echo "error: deploy the ServiceAccount-backed snapshot CronJob before verification" >&2
  exit 1
}

nodes=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o json)
jq -e '.items | length > 0 and all(.[];
  (.spec.unschedulable // false | not) and
  any(.status.conditions[]; .type == "Ready" and .status == "True"))' <<<"$nodes" >/dev/null || {
  echo "error: every control-plane node must be Ready and schedulable" >&2
  exit 1
}

run="$(date +%s)-$$"
while read -r node; do
  job="etcd-verify-$node-$run"
  # Preserve the deployed images, credentials, upload command and security
  # context. Only scheduling and retention differ from the hourly job.
  kubectl -n "$namespace" create job "$job" --from=cronjob/etcd-snapshot --dry-run=client -o json |
    jq --arg node "$node" '
      .spec.ttlSecondsAfterFinished = 86400 |
      .spec.template.spec.nodeSelector["kubernetes.io/hostname"] = $node
    ' | kubectl create -f - >/dev/null
  if ! kubectl -n "$namespace" wait --for=condition=Complete "job/$job" --timeout=10m; then
    echo "error: $job failed or timed out; inspect its snapshot and upload container logs. The legacy credential was retained." >&2
    exit 1
  fi
  echo "Snapshot and upload succeeded from $node ($job)"
done < <(jq -r '.items[].metadata.name' <<<"$nodes")

if $delete_legacy; then
  kubectl -n "$namespace" delete secret talos-snapshotter-config --ignore-not-found
fi
