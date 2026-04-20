#!/usr/bin/env bash
#MISE description "Tear down the local kind cluster created by runner:k8s:up"
#MISE raw=true

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-tuist-runners}"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    kind delete cluster --name "${CLUSTER_NAME}"
else
    echo "kind cluster '${CLUSTER_NAME}' does not exist, nothing to do"
fi
