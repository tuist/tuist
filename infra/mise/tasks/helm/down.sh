#!/usr/bin/env bash
#MISE description="Tear down the local kind cluster and Helm deployment"
#USAGE flag "--cluster <name>" help="Kind cluster name" default="tuist"

set -euo pipefail

echo "==> Stopping port-forwards..."
pkill -f "kubectl port-forward svc/${usage_cluster}-tuist" 2>/dev/null || true

echo "==> Deleting kind cluster '${usage_cluster}'..."
kind delete cluster --name "${usage_cluster}"
echo "==> Done."
