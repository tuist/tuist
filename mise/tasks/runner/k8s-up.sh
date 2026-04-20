#!/usr/bin/env bash
#MISE description "Bring up a local kind cluster and install the Tuist Runners CRD"
#MISE raw=true
#
# Creates a kind cluster named `tuist-runners` (idempotent), generates the
# Bonny operator manifest, and applies the CRD + RBAC so the Tuist Phoenix
# app can connect from outside the cluster and reconcile OrchardWorkerPool
# resources end-to-end against local stubs.
#
# After this runs:
#   - kubeconfig points at the kind cluster on kubectl's current context
#   - export TUIST_KUBECONFIG_PATH=$(kind get kubeconfig-path --name tuist-runners 2>/dev/null || echo ~/.kube/config)
#   - export TUIST_BONNY_ENABLED=true
#   - mise run dev
#   - mise run runner:k8s:apply-example

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-tuist-runners}"

cd "$(dirname "$0")/../../.."

if ! command -v kind >/dev/null 2>&1; then
    echo "ERROR: kind is not installed. Run 'mise install' from the repo root."
    exit 1
fi

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "==> kind cluster '${CLUSTER_NAME}' already exists"
else
    echo "==> Creating kind cluster '${CLUSTER_NAME}'..."
    kind create cluster --name "${CLUSTER_NAME}" --wait 60s
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo ""
echo "==> Generating CRD manifest via mix bonny.gen.manifest..."
cd server
mix bonny.gen.manifest --out "../tmp/bonny-manifest.yaml"
cd ..

echo "==> Applying CRD + RBAC..."
kubectl apply --context "kind-${CLUSTER_NAME}" -f tmp/bonny-manifest.yaml

echo ""
echo "==> Installed CRDs:"
kubectl --context "kind-${CLUSTER_NAME}" get crd | grep tuist.dev || true

echo ""
echo "Done. Next steps:"
echo "  export TUIST_KUBECONFIG_PATH=\$HOME/.kube/config"
echo "  export TUIST_BONNY_ENABLED=true"
echo "  mise run dev    # starts Phoenix with Bonny operator connected to kind"
echo "  mise run runner:k8s:apply-example"
