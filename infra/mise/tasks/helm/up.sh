#!/usr/bin/env bash
#MISE description="Deploy the full embedded Tuist stack to a local kind cluster"
#USAGE flag "--license <key>" help="License key for the Tuist server" required=#true
#USAGE flag "--cluster <name>" help="Kind cluster name" default="tuist"
#USAGE flag "--release <name>" help="Helm release name" default="tuist"
#USAGE flag "--remote" help="Use pre-built images from ghcr.io instead of building locally"
#USAGE flag "--version <version>" help="Image version tag when using --remote" default="latest"
#USAGE flag "--observability" help="Enable the embedded observability stack (Grafana, Prometheus, Loki, Tempo)"

set -euo pipefail

CLUSTER_NAME="${usage_cluster}"
RELEASE_NAME="${usage_release}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')"

if [ "${usage_remote:-}" = "true" ]; then
    SERVER_REPO="ghcr.io/tuist/tuist"
    CACHE_REPO="ghcr.io/tuist/cache"
    IMAGE_TAG="${usage_version}"
    echo "==> Pulling remote images for ${PLATFORM}..."
    docker pull --platform "$PLATFORM" "${SERVER_REPO}:${IMAGE_TAG}"
    docker pull --platform "$PLATFORM" "${CACHE_REPO}:${IMAGE_TAG}"
else
    SERVER_REPO="tuist-server"
    CACHE_REPO="tuist-cache"
    IMAGE_TAG="latest"

    echo "==> Building images locally..."
    mise run helm:build
fi

echo "==> Creating kind cluster '$CLUSTER_NAME' (if not exists)..."
if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    kind create cluster --name "$CLUSTER_NAME"
else
    echo "    Cluster '$CLUSTER_NAME' already exists, reusing."
fi

echo "==> Loading images into kind..."
if [ "${usage_remote:-}" = "true" ]; then
    kind load docker-image "${SERVER_REPO}:${IMAGE_TAG}" "${CACHE_REPO}:${IMAGE_TAG}" --name "$CLUSTER_NAME"
else
    kind load docker-image tuist-server:latest tuist-cache:latest --name "$CLUSTER_NAME"
fi

HELM_ARGS=(
    --set "server.image.repository=${SERVER_REPO}"
    --set "server.image.tag=${IMAGE_TAG}"
    --set "cache.image.repository=${CACHE_REPO}"
    --set "cache.image.tag=${IMAGE_TAG}"
    --set "server.license.key=${usage_license}"
    --set "server.appUrl=http://localhost:8080"
    --set "server.cacheEndpointUrl=http://localhost:8090"
)

if [ "${usage_observability:-}" = "true" ]; then
    HELM_ARGS+=(--set "observability.enabled=true")
fi

echo "==> Cleaning up previous release (ensures stale resources are removed)..."
if helm status "$RELEASE_NAME" >/dev/null 2>&1; then
    helm uninstall "$RELEASE_NAME" --wait 2>/dev/null || true
    kubectl delete pvc -l app.kubernetes.io/instance="$RELEASE_NAME" --wait=true 2>/dev/null || true
fi
kubectl delete job "${RELEASE_NAME}-tuist-server-migrate" --wait=true 2>/dev/null || true

echo "==> Installing Helm chart..."
helm install "$RELEASE_NAME" "$REPO_ROOT/infra/helm/tuist" \
    "${HELM_ARGS[@]}" \
    --wait --timeout 5m

echo "==> Waiting for pods..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance="$RELEASE_NAME" --timeout=120s 2>/dev/null || true

# Kill any existing port-forwards
pkill -f "kubectl port-forward svc/${RELEASE_NAME}-tuist" 2>/dev/null || true
sleep 1

echo "==> Starting port-forwards..."
kubectl port-forward svc/${RELEASE_NAME}-tuist-server 8080:80 &>/dev/null &
echo "    Server  → http://localhost:8080"
kubectl port-forward svc/${RELEASE_NAME}-tuist-cache 8090:80 &>/dev/null &
echo "    Cache   → http://localhost:8090"
if [ "${usage_observability:-}" = "true" ]; then
    kubectl port-forward svc/${RELEASE_NAME}-tuist-grafana 3001:3000 &>/dev/null &
    echo "    Grafana → http://localhost:3001"
fi

echo ""
echo "Stack is ready. Port-forwards are running in the background."
echo ""
echo "Other commands:"
echo "  mise run helm:status   # Check pod and service status"
echo "  mise run helm:down     # Tear down the cluster"
