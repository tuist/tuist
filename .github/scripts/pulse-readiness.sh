#!/usr/bin/env bash
# Read-only gate shared by routine deploys and managed migration qualification.
set -euo pipefail
trap 'echo "::error::Pulse readiness failed at line $LINENO; collectors were not changed."' ERR
: "${DEPLOY_ENV:?managed environment required}"
case "$DEPLOY_ENV" in staging|canary|production) ;; *) exit 1 ;; esac
namespace=${OBSERVABILITY_NAMESPACE:-observability}
deployment=$(kubectl -n "$namespace" get deployment pulse --ignore-not-found -o json)
# The old pulse release is uninstalled once no collector writes to it. Gate
# on the Greptime backend when one is installed; a cluster with neither
# still gets Grafana Cloud collection.
if [[ -z "$deployment" ]]; then
  if [[ -n "$(kubectl -n "$namespace" get statefulset greptimedb greptimedb-datanode --ignore-not-found -o name)" ]]; then
    greptime=true
  else
    greptime=none
  fi
else
jq -e '
  .metadata.annotations["meta.helm.sh/release-name"] == "pulse" and
  .metadata.annotations["meta.helm.sh/release-namespace"] == "observability" and
  .spec.replicas == 1 and .spec.strategy.type == "Recreate" and
  .status.observedGeneration >= .metadata.generation and
  .status.updatedReplicas == 1 and .status.readyReplicas == 1 and .status.availableReplicas == 1 and
  (.spec.template.spec.containers | length == 1)
' <<< "$deployment" >/dev/null
if jq -e '.metadata.labels["app.kubernetes.io/name"] == "greptimedb-ingest"' <<< "$deployment" >/dev/null; then
  # Select by the live runtime, not an environment-wide migration flag. Legacy
  # Pulse deployments still do not depend on a Greptime StatefulSet existing.
  jq -e '.spec.template.spec.containers[0].image == "nginxinc/nginx-unprivileged:1.28.0-alpine"' <<< "$deployment" >/dev/null
  greptime=true
  origin="Greptime gateway and"
else
  jq -e '.spec.template.spec.containers[0].image |
    test("^ghcr.io/tuist/pulse:[0-9]+\\.[0-9]+\\.[0-9]+@sha256:[0-9a-f]{64}$")' <<< "$deployment" >/dev/null
  greptime=false
fi
fi
if [[ "$greptime" == true ]]; then
  # The chart's topology decides which backend workloads must be ready.
  if [[ -n "$(kubectl -n "$namespace" get statefulset greptimedb-datanode --ignore-not-found -o name)" ]]; then
    workloads='statefulset/greptimedb-etcd:3 statefulset/greptimedb-kafka:3 deployment/greptimedb-metasrv:3 statefulset/greptimedb-datanode:3 deployment/greptimedb-frontend:2'
    topology=cluster
  else
    workloads='statefulset/greptimedb:1'
    topology=standalone
  fi
  for entry in $workloads; do
    workload=${entry%:*}
    kubectl -n "$namespace" get "${workload%/*}" "${workload#*/}" -o json | jq -e --argjson minimum "${entry##*:}" --arg topology "$topology" '
      .metadata.annotations["meta.helm.sh/release-name"] == "greptimedb" and
      .metadata.annotations["meta.helm.sh/release-namespace"] == "observability" and
      .spec.replicas >= $minimum and ($topology == "cluster" or .spec.replicas == 1) and .status.observedGeneration >= .metadata.generation and
      (.kind != "StatefulSet" or .status.currentRevision == .status.updateRevision) and
      .status.updatedReplicas == .spec.replicas and .status.readyReplicas == .spec.replicas and
      ((.metadata.name | test("-(etcd|kafka)$")) or
        [.spec.template.spec.containers[].image] == ["docker.io/greptime/greptimedb:v1.3.0"])
    ' >/dev/null
  done
  backend="${origin:-Greptime} $topology backend"
elif [[ "$greptime" == none ]]; then
  backend='no Pulse backend installed (Grafana Cloud only)'
else
  backend='existing Pulse (Greptime is not required)'
fi
legacy=$(kubectl -n "$namespace" get deployment pulso --ignore-not-found -o json)
if [[ -n "$legacy" ]]; then jq -e '.spec.replicas == 0' <<< "$legacy" >/dev/null; fi
kubectl -n "$namespace" get pods -o json | jq -e '
  all(.items[]; all(.spec.containers[];
    (.image | test("^ghcr.io/tuist/pulso(:|@|$)")) | not))' >/dev/null
# Alloy fails its whole config load, Grafana Cloud included, when a
# referenced Secret is missing. Collectors that write to Greptime need its
# ingest login to exist first; check its ExternalSecret, never the Secret.
values="${OBSERVABILITY_CHART_PATH:-}/values-$DEPLOY_ENV.yaml"
if [[ -n "${OBSERVABILITY_CHART_PATH:-}" ]] && grep -q 'greptimedb-dashboard-auth' "$values"; then
  kubectl -n "$namespace" get externalsecret greptimedb-dashboard-auth -o json | jq -e '
    (.spec.target.template.data | has("ingest-username") and has("ingest-password")) and
    any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null || {
    echo "::error::Collectors write to Greptime, but its ingest login is not ready; deploy the backend with dashboard=true first."
    exit 1
  }
fi
echo "PASS: $backend ready; no legacy writers"
