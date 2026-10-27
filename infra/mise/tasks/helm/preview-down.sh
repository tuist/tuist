#!/usr/bin/env bash
#MISE description="Tear down the multi-node preview kind cluster"
#USAGE flag "--cluster <name>" help="Kind cluster name" default="tuist-preview"

set -euo pipefail

echo "==> Deleting kind cluster '${usage_cluster}'..."
kind delete cluster --name "${usage_cluster}"
echo "==> Done."
