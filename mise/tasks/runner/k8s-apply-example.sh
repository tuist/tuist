#!/usr/bin/env bash
#MISE description "Apply an example OrchardWorkerPool to the local kind cluster"
#MISE raw=true
#USAGE arg "<account_id>" help="Tuist account id to attach the pool to (use `tuistrocks@tuist.dev`'s account for local dev)"
#USAGE arg "[desired_size]" help="Desired replica count (default 2)"

set -euo pipefail

cd "$(dirname "$0")/../../.."

ACCOUNT_ID="${usage_account_id?}"
DESIRED_SIZE="${usage_desired_size:-2}"
CLUSTER_NAME="${CLUSTER_NAME:-tuist-runners}"
POOL_NAME="${POOL_NAME:-dev-pool}"

cat <<MANIFEST | kubectl apply --context "kind-${CLUSTER_NAME}" -f -
apiVersion: tuist.dev/v1
kind: OrchardWorkerPool
metadata:
  name: ${POOL_NAME}
spec:
  accountId: ${ACCOUNT_ID}
  desiredSize: ${DESIRED_SIZE}
  scalewayZone: fr-par-3
  scalewayServerType: M1-M
  scalewayOs: macos-tahoe-26.0
MANIFEST

echo ""
echo "Applied. Watch reconciliation progress:"
echo "  kubectl --context kind-${CLUSTER_NAME} get owp -o wide"
echo "  kubectl --context kind-${CLUSTER_NAME} describe owp ${POOL_NAME}"
