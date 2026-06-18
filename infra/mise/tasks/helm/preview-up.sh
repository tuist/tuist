#!/usr/bin/env bash
#MISE description="Spin up a multi-node kind cluster and deploy a preview release pinned to role=preview node"
#USAGE flag "--cluster <name>" help="Kind cluster name" default="tuist-preview"
#USAGE flag "--release <name>" help="Helm release name" default="pr-demo"
#USAGE flag "--remote" help="Use pre-built images from ghcr.io instead of building locally"
#USAGE flag "--version <version>" help="Image version tag when using --remote" default="latest"
#USAGE flag "--with-kura" help="Also enable the Kura controller and create a shared private two-node KuraInstance"
#USAGE flag "--kura-controller-image <image>" help="Kura controller image repository for local kind" default="tuist-kura-controller"
#USAGE flag "--kura-runtime-image <image>" help="Kura runtime image repository for local kind" default="tuist-kura"
#USAGE flag "--kura-image-tag <tag>" help="Kura controller/runtime image tag for local kind" default="kind"
#
# Two license-source modes, picked by which env var is exported:
#
#   $OP_SERVICE_ACCOUNT_TOKEN  → "prod-shape" path. Installs External Secrets
#                                Operator + a 1Password ClusterSecretStore in
#                                the kind cluster. The chart's ExternalSecret
#                                pulls the license from item TUIST_LICENSE_KEY
#                                in 1Password. Mirrors how the managed
#                                clusters are configured (see infra/k8s/onboarding.md).
#
#   $TUIST_LICENSE_KEY         → local fallback. Skips ESO and inlines the key
#                                so kind clusters without 1P access still work.
#                                Only for local development; never commit
#                                values that include the plaintext.
#
# CI should always go through the OP_SERVICE_ACCOUNT_TOKEN path: source the
# token from the platform's secret store (GitHub Actions, Vault) and export it
# before invoking this task.

set -euo pipefail

CLUSTER_NAME="${usage_cluster}"
RELEASE_NAME="${usage_release}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')"
WITH_KURA="${usage_with_kura:-false}"
KURA_CONTROLLER_REPO="${usage_kura_controller_image}"
KURA_RUNTIME_REPO="${usage_kura_runtime_image}"
KURA_IMAGE_TAG="${usage_kura_image_tag}"
KURA_INSTANCE_NAME="${RELEASE_NAME}-kura"
KURA_ENDPOINT_URL="http://${KURA_INSTANCE_NAME}.kura.svc.cluster.local:4000"

if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    LICENSE_MODE="eso"
elif [ -n "${TUIST_LICENSE_KEY:-}" ]; then
    LICENSE_MODE="inline"
else
    echo "ERROR: set either OP_SERVICE_ACCOUNT_TOKEN (preferred, ESO path)" >&2
    echo "       or TUIST_LICENSE_KEY (local fallback) before running." >&2
    exit 1
fi
echo "==> License source: $LICENSE_MODE"

if [ "${usage_remote:-}" = "true" ]; then
    SERVER_REPO="ghcr.io/tuist/tuist"
    CACHE_REPO="ghcr.io/tuist/cache"
    IMAGE_TAG="${usage_version}"
    echo "==> Pulling remote images for ${PLATFORM}..."
    docker pull --platform "$PLATFORM" "${SERVER_REPO}:${IMAGE_TAG}"
    docker pull --platform "$PLATFORM" "${CACHE_REPO}:${IMAGE_TAG}"
    if [ "$WITH_KURA" = "true" ]; then
        KURA_CONTROLLER_REPO="ghcr.io/tuist/kura-controller"
        KURA_RUNTIME_REPO="ghcr.io/tuist/kura"
        KURA_IMAGE_TAG="${usage_version}"
        docker pull --platform "$PLATFORM" "${KURA_CONTROLLER_REPO}:${KURA_IMAGE_TAG}"
        docker pull --platform "$PLATFORM" "${KURA_RUNTIME_REPO}:${KURA_IMAGE_TAG}"
    fi
else
    SERVER_REPO="tuist-server"
    CACHE_REPO="tuist-cache"
    IMAGE_TAG="latest"
    echo "==> Building images locally..."
    mise run helm:build
    if [ "$WITH_KURA" = "true" ]; then
        echo "==> Building Kura controller image locally..."
        docker build \
            --platform "$PLATFORM" \
            -f "$REPO_ROOT/infra/kura-controller/Dockerfile" \
            -t "${KURA_CONTROLLER_REPO}:${KURA_IMAGE_TAG}" \
            "$REPO_ROOT"

        echo "==> Building Kura runtime image locally..."
        docker build \
            --platform "$PLATFORM" \
            -t "${KURA_RUNTIME_REPO}:${KURA_IMAGE_TAG}" \
            "$REPO_ROOT/kura"
    fi
fi

echo "==> Creating multi-node kind cluster '$CLUSTER_NAME' (control-plane + general worker + preview worker)..."
if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    kind create cluster --name "$CLUSTER_NAME" --config "$REPO_ROOT/infra/k8s/kind-preview.yaml"
else
    echo "    Cluster '$CLUSTER_NAME' already exists, reusing."
fi

echo "==> Verifying node labels and taints..."
kubectl get nodes -L role
kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints) | "\(.metadata.name): \(.spec.taints[] | "\(.key)=\(.value):\(.effect)")"'

echo "==> Loading images into kind..."
kind load docker-image "${SERVER_REPO}:${IMAGE_TAG}" "${CACHE_REPO}:${IMAGE_TAG}" --name "$CLUSTER_NAME"
if [ "$WITH_KURA" = "true" ]; then
    kind load docker-image \
        "${KURA_CONTROLLER_REPO}:${KURA_IMAGE_TAG}" \
        "${KURA_RUNTIME_REPO}:${KURA_IMAGE_TAG}" \
        --name "$CLUSTER_NAME"
fi

HELM_LICENSE_ARGS=()

if [ "$LICENSE_MODE" = "eso" ]; then
    echo "==> Installing External Secrets Operator..."
    helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
    helm repo update external-secrets >/dev/null
    helm upgrade --install external-secrets external-secrets/external-secrets \
        -n external-secrets --create-namespace \
        --set installCRDs=true \
        --wait --timeout 3m

    echo "==> Configuring 1Password ClusterSecretStore..."
    # Mirrors infra/k8s/onboarding.md: SA token Secret lives in the
    # `onepassword` namespace, store uses the onepasswordSDK provider (matches
    # the "<item>/<field>" remoteRef syntax in templates/external-secrets.yaml).
    kubectl create namespace onepassword --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n onepassword delete secret onepassword-sa-token --ignore-not-found
    kubectl -n onepassword create secret generic onepassword-sa-token \
        --from-literal=token="$OP_SERVICE_ACCOUNT_TOKEN"

    cat <<'EOF' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepasswordSDK:
      vault: tuist-k8s-preview
      auth:
        serviceAccountSecretRef:
          name: onepassword-sa-token
          namespace: onepassword
          key: token
EOF

    echo "==> Waiting for ClusterSecretStore to go Ready..."
    kubectl wait --for=condition=Ready clustersecretstore/onepassword --timeout=60s

    # The chart's preview overlay already sets
    # server.externalSecrets.license.item=TUIST_LICENSE_KEY; nothing else to
    # pass here. helm waits for the migration job, which transitively waits
    # for the ExternalSecret target Secret to materialize.
else
    echo "==> Local fallback: license will be inlined (no ESO)."
    HELM_LICENSE_ARGS=(
        --set "server.externalSecrets.license.item="
        --set "server.license.key=${TUIST_LICENSE_KEY}"
    )
fi

echo "==> Cleaning up previous release if any..."
if helm status "$RELEASE_NAME" >/dev/null 2>&1; then
    helm uninstall "$RELEASE_NAME" --wait 2>/dev/null || true
    kubectl delete pvc -l app.kubernetes.io/instance="$RELEASE_NAME" --wait=true 2>/dev/null || true
fi
if [ "$WITH_KURA" = "true" ]; then
    kubectl -n kura delete kurainstance "$KURA_INSTANCE_NAME" --ignore-not-found --wait=true 2>/dev/null || true
fi

HELM_VALUES_ARGS=(-f "$REPO_ROOT/infra/helm/tuist/values-preview.yaml")
HELM_KURA_ARGS=()
if [ "$WITH_KURA" = "true" ]; then
    HELM_VALUES_ARGS+=(-f "$REPO_ROOT/infra/helm/tuist/values-preview-kura.yaml")
    HELM_KURA_ARGS=(
        --set "kuraController.image.repository=${KURA_CONTROLLER_REPO}"
        --set "kuraController.image.tag=${KURA_IMAGE_TAG}"
        --set "kuraRuntime.image.repository=${KURA_RUNTIME_REPO}"
        --set "kuraRuntime.image.tag=${KURA_IMAGE_TAG}"
        --set "server.kuraEndpointUrls[0]=${KURA_ENDPOINT_URL}"
    )
fi

echo "==> Installing preview release..."
helm install "$RELEASE_NAME" "$REPO_ROOT/infra/helm/tuist" \
    "${HELM_VALUES_ARGS[@]}" \
    --set "server.image.repository=${SERVER_REPO}" \
    --set "server.image.tag=${IMAGE_TAG}" \
    --set "cache.image.repository=${CACHE_REPO}" \
    --set "cache.image.tag=${IMAGE_TAG}" \
    --set "server.appUrl=http://${RELEASE_NAME}.preview.local" \
    --set "server.cacheEndpointUrl=http://${RELEASE_NAME}-cache.preview.local" \
    "${HELM_LICENSE_ARGS[@]}" \
    "${HELM_KURA_ARGS[@]}" \
    --wait --timeout 5m

if [ "$WITH_KURA" = "true" ]; then
    echo "==> Creating shared private KuraInstance '${KURA_INSTANCE_NAME}' on role=kura nodes..."
    {
        cat <<EOF
apiVersion: kura.tuist.dev/v1alpha1
kind: KuraInstance
metadata:
  name: ${KURA_INSTANCE_NAME}
  namespace: kura
  labels:
    tuist.dev/preview-source: slack
    app.kubernetes.io/instance: ${RELEASE_NAME}
    tuist.dev/shared: "true"
spec:
  accountHandle: preview-${RELEASE_NAME}
  tenantID: preview-${RELEASE_NAME}
  region: kind-local
  image: ${KURA_RUNTIME_REPO}:${KURA_IMAGE_TAG}
  replicas: 2
  private: true
  storageSize: 1Gi
  extraEnv:
    - name: KURA_CONTROL_PLANE_URL
      value: http://${RELEASE_NAME}-tuist-server.default.svc.cluster.local:80
    - name: KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL
      value: http://${RELEASE_NAME}-tuist-server.default.svc.cluster.local:80
    - name: KURA_EXTENSION_TUIST_ALLOW_SHARED_TENANTS
      value: "1"
  nodeSelector:
    role: kura
  extensionScript: |
EOF
        sed 's/^/    /' "$REPO_ROOT/kura/ops/helm/kura/hooks/tuist.lua"
    } | kubectl apply -f -

    echo "==> Waiting for KuraInstance controller output..."
    kubectl -n kura wait --for=condition=Available deployment/"${RELEASE_NAME}-tuist-kura-controller" --timeout=3m
    for _ in $(seq 1 60); do
        if kubectl -n kura get statefulset "$KURA_INSTANCE_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
    kubectl -n kura rollout status statefulset/"$KURA_INSTANCE_NAME" --timeout=10m
fi

echo ""
echo "==> Pod placement (every pod should land on a role=preview worker):"
kubectl get pods -l app.kubernetes.io/instance="$RELEASE_NAME" -o wide

echo ""
echo "==> Verifying pinning..."
UNEXPECTED=$(kubectl get pods -l app.kubernetes.io/instance="$RELEASE_NAME" \
    -o json | jq -r '.items[] | select(.spec.nodeName != null) |
    "\(.metadata.name) \(.spec.nodeName)"' \
    | while read -r pod node; do
        role="$(kubectl get node "$node" -o jsonpath='{.metadata.labels.role}')"
        if [ "$role" != "preview" ]; then
            echo "$pod $node role=$role"
        fi
    done)
if [ -n "$UNEXPECTED" ]; then
    echo "    FAIL: pods scheduled outside role=preview workers:"
    echo "$UNEXPECTED"
    exit 1
fi
echo "    OK: all preview pods landed on role=preview workers."

if [ "$WITH_KURA" = "true" ]; then
    echo ""
    echo "==> Kura pod placement (Kura runtime pods should land on role=kura workers):"
    kubectl -n kura get pods -l app.kubernetes.io/instance="$KURA_INSTANCE_NAME" -o wide
    KURA_UNEXPECTED=$(kubectl -n kura get pods -l app.kubernetes.io/instance="$KURA_INSTANCE_NAME" \
        -o json | jq -r '.items[] | select(.spec.nodeName != null) |
        "\(.metadata.name) \(.spec.nodeName)"' \
        | while read -r pod node; do
            role="$(kubectl get node "$node" -o jsonpath='{.metadata.labels.role}')"
            if [ "$role" != "kura" ]; then
                echo "$pod $node role=$role"
            fi
        done)
    if [ -n "$KURA_UNEXPECTED" ]; then
        echo "    FAIL: Kura pods scheduled outside role=kura workers:"
        echo "$KURA_UNEXPECTED"
        exit 1
    fi
    echo "    OK: Kura runtime pods landed on role=kura workers."
fi

echo ""
echo "Tear down with: mise run helm:preview-down"
