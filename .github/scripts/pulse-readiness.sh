#!/usr/bin/env bash
# Read-only gate shared by routine deploys and the Pulse backend deployment.
set -euo pipefail
trap 'echo "::error::Pulse readiness failed at line $LINENO; collectors were not changed."' ERR
: "${DEPLOY_ENV:?managed environment required}"
case "$DEPLOY_ENV" in staging|canary|production) ;; *) exit 1 ;; esac
namespace=${OBSERVABILITY_NAMESPACE:-observability}
# Pulse is the `pulse` release of infra/helm/greptimedb. Gate on it when it is
# installed; a cluster without it still gets Grafana Cloud collection.
if [[ -n "$(kubectl -n "$namespace" get statefulset pulse-datanode --ignore-not-found -o name)" ]]; then
  workloads='statefulset/pulse-etcd:3 statefulset/pulse-kafka:3 deployment/pulse-metasrv:3 statefulset/pulse-datanode:3 deployment/pulse-frontend:2'
  topology=cluster
elif [[ -n "$(kubectl -n "$namespace" get statefulset pulse --ignore-not-found -o name)" ]]; then
  workloads='statefulset/pulse:1'
  topology=standalone
else
  topology=
fi
for entry in ${workloads:-}; do
  workload=${entry%:*}
  # Any published Pulse release passes, so pinning a newer one in the chart
  # does not block server deploys until the backend is redeployed: a stable,
  # canary or RC version, or a <upstream>-<n> fork release from before Pulse
  # owned its versions (1.3.0-2).
  kubectl -n "$namespace" get "${workload%/*}" "${workload#*/}" -o json | jq -e --argjson minimum "${entry##*:}" --arg topology "$topology" '
    .metadata.annotations["meta.helm.sh/release-name"] == "pulse" and
    .metadata.annotations["meta.helm.sh/release-namespace"] == "observability" and
    .spec.replicas >= $minimum and ($topology == "cluster" or .spec.replicas == 1) and .status.observedGeneration >= .metadata.generation and
    (.kind != "StatefulSet" or .status.currentRevision == .status.updateRevision) and
    .status.updatedReplicas == .spec.replicas and .status.readyReplicas == .spec.replicas and
    ((.metadata.name | test("-(etcd|kafka)$")) or
      ([.spec.template.spec.containers[].image] | length == 1 and
        all(test("^ghcr\\.io/tuist/pulse:[0-9]+\\.[0-9]+\\.[0-9]+(-(canary|rc)\\.[0-9]+|-[0-9]+)?$"))))
  ' >/dev/null
done
if [[ -n "$topology" ]]; then
  backend="Pulse $topology backend ready"
else
  backend='no Pulse backend installed (Grafana Cloud only)'
fi
# Alloy fails its whole config load, Grafana Cloud included, when a
# referenced Secret is missing. Collectors that write to Pulse need its
# ingest login to exist first; check its ExternalSecret, never the Secret.
values="${OBSERVABILITY_CHART_PATH:-}/values-$DEPLOY_ENV.yaml"
if [[ -n "${OBSERVABILITY_CHART_PATH:-}" ]] && grep -q 'pulse-dashboard-auth' "$values"; then
  kubectl -n "$namespace" get externalsecret pulse-dashboard-auth -o json | jq -e '
    (.spec.target.template.data | has("ingest-username") and has("ingest-password")) and
    any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null || {
    echo "::error::Collectors write to Pulse, but its ingest login is not ready; deploy the backend with dashboard=true first."
    exit 1
  }
fi
echo "PASS: $backend"
