#!/usr/bin/env bash
#MISE description="Render the ClusterClass control-plane patches and fail if one drops another's API server flags, volumes or files"

# See infra/k8s/clusters/clusterclass-check/main.go for what is checked and
# why. The checker is its own module, outside go.work.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT/infra/k8s/clusters/clusterclass-check"
GOWORK=off go run . "$REPO_ROOT/infra/k8s/clusters/clusterclass-tuist.yaml"
