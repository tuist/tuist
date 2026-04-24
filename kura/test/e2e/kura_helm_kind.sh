#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kura-helm}"
NAMESPACE="${NAMESPACE:-kura}"
RELEASE_NAME="${RELEASE_NAME:-kura}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-kura}"
IMAGE_TAG="${IMAGE_TAG:-kind}"
HTTP_PORT_0="${HTTP_PORT_0:-18081}"
HTTP_PORT_1="${HTTP_PORT_1:-18082}"

cleanup() {
  if [[ -n "${PF0_PID:-}" ]]; then
    kill "${PF0_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PF1_PID:-}" ]]; then
    kill "${PF1_PID}" >/dev/null 2>&1 || true
  fi
  kind delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
}

trap cleanup EXIT

docker build -t "${IMAGE_REPOSITORY}:${IMAGE_TAG}" .

kind create cluster --name "${CLUSTER_NAME}"
kind load docker-image "${IMAGE_REPOSITORY}:${IMAGE_TAG}" --name "${CLUSTER_NAME}"

helm upgrade --install "${RELEASE_NAME}" ./ops/helm/kura \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout 10m \
  --set replicaCount=2 \
  --set persistence.enabled=false \
  --set image.repository="${IMAGE_REPOSITORY}" \
  --set image.tag="${IMAGE_TAG}" \
  --set image.pullPolicy=IfNotPresent \
  --set config.region=kind-local \
  --set config.telemetry.otlpTracesEndpoint=http://127.0.0.1:4318/v1/traces

kubectl rollout status statefulset/"${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=5m

kubectl port-forward -n "${NAMESPACE}" "pod/${RELEASE_NAME}-0" "${HTTP_PORT_0}:4000" >/tmp/kura-helm-pf-0.log 2>&1 &
PF0_PID=$!
kubectl port-forward -n "${NAMESPACE}" "pod/${RELEASE_NAME}-1" "${HTTP_PORT_1}:4000" >/tmp/kura-helm-pf-1.log 2>&1 &
PF1_PID=$!

for port in "${HTTP_PORT_0}" "${HTTP_PORT_1}"; do
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${port}/up" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
done

curl -fsS -X POST \
  "http://127.0.0.1:${HTTP_PORT_0}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
  -H "content-type: application/octet-stream" \
  --data-binary "xcode-binary" >/dev/null

for _ in $(seq 1 60); do
  if [[ "$(curl -fsS "http://127.0.0.1:${HTTP_PORT_1}/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" 2>/dev/null || true)" == "xcode-binary" ]]; then
    echo "Helm smoke test passed"
    exit 0
  fi
  sleep 2
done

echo "Timed out waiting for replicated artifact on pod 1" >&2
exit 1
