#!/usr/bin/env bash
# Read-only gate shared by routine deploys and staging migration qualification.
set -euo pipefail
trap 'echo "::error::Pulse readiness failed at line $LINENO; collectors were not changed."' ERR
: "${DEPLOY_ENV:?managed environment required}"
case "$DEPLOY_ENV" in staging|canary|production) ;; *) exit 1 ;; esac
namespace=${OBSERVABILITY_NAMESPACE:-observability}
deployment=$(kubectl -n "$namespace" get deployment pulse -o json)
jq -e '
  .metadata.annotations["meta.helm.sh/release-name"] == "pulse" and
  .metadata.annotations["meta.helm.sh/release-namespace"] == "observability" and
  .spec.replicas == 1 and .spec.strategy.type == "Recreate" and
  .status.observedGeneration >= .metadata.generation and
  .status.updatedReplicas == 1 and .status.readyReplicas == 1 and .status.availableReplicas == 1 and
  (.spec.template.spec.containers | length == 1)
' <<< "$deployment" >/dev/null
if jq -e '.metadata.labels["app.kubernetes.io/name"] == "greptimedb-ingest"' <<< "$deployment" >/dev/null; then
  # Only staging may use the replacement. Existing Pulse deployments in other
  # environments must not depend on a Greptime StatefulSet even existing.
  [[ "$DEPLOY_ENV" == staging ]]
  jq -e '.spec.template.spec.containers[0].image == "nginxinc/nginx-unprivileged:1.28.0-alpine"' <<< "$deployment" >/dev/null
  kubectl -n "$namespace" get statefulset greptimedb -o json | jq -e '
    .metadata.annotations["meta.helm.sh/release-name"] == "greptimedb" and
    .metadata.annotations["meta.helm.sh/release-namespace"] == "observability" and
    .spec.replicas == 1 and .status.observedGeneration >= .metadata.generation and
    .status.currentRevision == .status.updateRevision and
    .status.updatedReplicas == 1 and .status.readyReplicas == 1 and
    ([.spec.template.spec.containers[].image] == ["docker.io/greptime/greptimedb:v1.3.0"])
  ' >/dev/null
  backend='staging Greptime gateway and backend'
else
  jq -e '.spec.template.spec.containers[0].image |
    test("^ghcr.io/tuist/pulse:[0-9]+\\.[0-9]+\\.[0-9]+@sha256:[0-9a-f]{64}$")' <<< "$deployment" >/dev/null
  backend='existing Pulse (Greptime is not required)'
fi
legacy=$(kubectl -n "$namespace" get deployment pulso --ignore-not-found -o json)
if [[ -n "$legacy" ]]; then jq -e '.spec.replicas == 0' <<< "$legacy" >/dev/null; fi
kubectl -n "$namespace" get pods -o json | jq -e '
  all(.items[]; all(.spec.containers[];
    (.image | test("^ghcr.io/tuist/pulso(:|@|$)")) | not))' >/dev/null
echo "PASS: $backend ready; no legacy writers"
