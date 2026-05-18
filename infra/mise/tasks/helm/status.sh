#!/usr/bin/env bash
#MISE description="Show the status of the local Helm deployment"
#USAGE flag "--release <name>" help="Helm release name" default="tuist"

set -euo pipefail

echo "==> Helm release:"
helm status "${usage_release}" 2>/dev/null || echo "    No release found."

echo ""
echo "==> Pods:"
kubectl get pods -l app.kubernetes.io/instance="${usage_release}" 2>/dev/null || echo "    No pods found."

echo ""
echo "==> Services:"
kubectl get svc -l app.kubernetes.io/instance="${usage_release}" 2>/dev/null || echo "    No services found."
