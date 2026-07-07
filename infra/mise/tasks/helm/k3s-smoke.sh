#!/usr/bin/env bash
#MISE description="Smoke test the Tuist Helm chart on a disposable K3s cluster"
#USAGE flag "--render-only" help="Only lint and render the chart without creating a cluster"
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
CHART="${ROOT}/infra/helm/tuist"
VALUES="${CHART}/values-k3s-smoke.yaml"
RELEASE="${TUIST_HELM_K3S_RELEASE:-tuist}"
NAMESPACE="${TUIST_HELM_K3S_NAMESPACE:-tuist}"
CLUSTER="${TUIST_HELM_K3S_CLUSTER:-tuist-helm-smoke}"
KEEP_CLUSTER="${TUIST_HELM_K3S_KEEP_CLUSTER:-0}"
USE_CURRENT_CONTEXT="${TUIST_HELM_K3S_USE_CURRENT_CONTEXT:-0}"
KUBECTL_BIN="${KUBECTL:-kubectl}"
RENDER_ONLY="${usage_render_only:-false}"

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name" >&2
        exit 1
    fi
}

require_command helm
require_command "$KUBECTL_BIN"

rendered="$(mktemp)"
cleanup_rendered() {
    rm -f "$rendered"
}
trap cleanup_rendered EXIT

if grep -q "^dependencies:" "${CHART}/Chart.yaml"; then
    helm dependency update "$CHART"
fi

helm lint "$CHART" -f "$VALUES"
helm template "$RELEASE" "$CHART" --include-crds -f "$VALUES" > "$rendered"
echo "Rendered $(wc -l <"$rendered") lines of manifests."

if [[ "$RENDER_ONLY" == "true" ]]; then
    exit 0
fi

created_cluster=0

collect_diagnostics() {
    local exit_code=$?
    rm -f "$rendered"

    if [[ "$exit_code" -ne 0 ]]; then
        "$KUBECTL_BIN" -n "$NAMESPACE" get all,pvc || true
        "$KUBECTL_BIN" -n "$NAMESPACE" get events --sort-by=.lastTimestamp || true
        "$KUBECTL_BIN" -n "$NAMESPACE" describe pods || true
    fi

    if [[ "$created_cluster" == "1" && "$KEEP_CLUSTER" != "1" ]]; then
        k3d cluster delete "$CLUSTER" >/dev/null 2>&1 || true
    fi

    exit "$exit_code"
}
trap collect_diagnostics EXIT

if [[ "$USE_CURRENT_CONTEXT" != "1" ]]; then
    require_command docker
    require_command k3d

    if ! docker info >/dev/null 2>&1; then
        echo "Docker must be running to create the disposable k3d cluster." >&2
        exit 1
    fi

    if ! k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
        k3d cluster create "$CLUSTER" \
            --servers 1 \
            --agents 0 \
            --k3s-arg "--disable=traefik@server:*" \
            --wait
        created_cluster=1
    fi

    export KUBECONFIG
    KUBECONFIG="$(k3d kubeconfig write "$CLUSTER")"
fi

"$KUBECTL_BIN" wait --for=condition=Ready nodes --all --timeout=120s
node_versions="$("$KUBECTL_BIN" get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}')"
if ! grep -qi "k3s" <<< "$node_versions"; then
    echo "The current Kubernetes context is not backed by K3s:" >&2
    echo "$node_versions" >&2
    echo "Set TUIST_HELM_K3S_USE_CURRENT_CONTEXT=0 to let the task create a disposable k3d cluster." >&2
    exit 1
fi

"$KUBECTL_BIN" get nodes -o wide
"$KUBECTL_BIN" get storageclass
"$KUBECTL_BIN" create namespace "$NAMESPACE" --dry-run=client -o yaml | "$KUBECTL_BIN" apply -f -
"$KUBECTL_BIN" apply --dry-run=server -n "$NAMESPACE" -f "$rendered"

helm upgrade --install "$RELEASE" "$CHART" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$VALUES" \
    --timeout 10m

"$KUBECTL_BIN" -n "$NAMESPACE" rollout status "statefulset/${RELEASE}-tuist-postgresql" --timeout=180s
"$KUBECTL_BIN" -n "$NAMESPACE" rollout status "statefulset/${RELEASE}-tuist-clickhouse" --timeout=240s
"$KUBECTL_BIN" -n "$NAMESPACE" rollout status "statefulset/${RELEASE}-tuist-object-storage" --timeout=180s
"$KUBECTL_BIN" -n "$NAMESPACE" wait --for=condition=complete "job/${RELEASE}-tuist-clickhouse-init" --timeout=240s
"$KUBECTL_BIN" -n "$NAMESPACE" wait --for=condition=complete "job/${RELEASE}-tuist-object-storage-init" --timeout=240s
"$KUBECTL_BIN" -n "$NAMESPACE" get pods,jobs,pvc
