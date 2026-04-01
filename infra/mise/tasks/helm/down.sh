#!/usr/bin/env bash
#MISE description="Tear down the local kind cluster and Helm deployment"
#USAGE flag "--cluster <name>" help="Kind cluster name" default="tuist"

set -euo pipefail

echo "==> Deleting kind cluster '${usage_cluster}'..."
kind delete cluster --name "${usage_cluster}"
echo "==> Done."
