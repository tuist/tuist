#!/usr/bin/env bash
#MISE description="Assert KUBERNETES_VERSION in clusterclass-tuist.yaml matches topology.version on every per-env Cluster CR"

# The ClusterClass pins kubelet/kubeadm/kubectl via apt
# (KUBERNETES_VERSION in preKubeadmCommands). The per-env Cluster CRs
# pin what KCP renders into the static pod manifests
# (topology.version). They MUST stay aligned: divergence means new
# nodes join with mismatched components.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CC="$REPO_ROOT/infra/k8s/clusters/clusterclass-tuist.yaml"

# Single source of truth: the apt install pin in preKubeadmCommands.
CC_VERSION=$(grep -E '^\s+- export KUBERNETES_VERSION=' "$CC" \
  | head -1 \
  | sed -E 's/.*KUBERNETES_VERSION=v?//' \
  | tr -d ' ')

if [ -z "$CC_VERSION" ]; then
  echo "ERROR: could not parse KUBERNETES_VERSION from $CC" >&2
  exit 2
fi

drift=0
# Both layouts: the flat CRs still applied by mgmt-cluster-apply.yml
# (preview, pentest) AND the Flux-reconciled ones under workloads/.
# Globbing only cluster-*.yaml silently stopped covering staging /
# canary / production / tenants when they moved into workloads/.
for f in "$REPO_ROOT"/infra/k8s/clusters/cluster-*.yaml \
         "$REPO_ROOT"/infra/k8s/clusters/workloads/*/cluster.yaml; do
  [ -e "$f" ] || continue
  topo=$(grep -E '^\s+version:\s+v?[0-9]+\.[0-9]+\.[0-9]+' "$f" \
    | head -1 \
    | awk '{print $2}' \
    | sed 's/^v//')
  if [ -z "$topo" ]; then
    echo "WARN: ${f#"$REPO_ROOT"/infra/k8s/clusters/} has no topology.version line" >&2
    continue
  fi
  if [ "$topo" != "$CC_VERSION" ]; then
    echo "DRIFT: ${f#"$REPO_ROOT"/infra/k8s/clusters/}: topology.version=$topo  vs  ClusterClass KUBERNETES_VERSION=$CC_VERSION"
    drift=1
  fi
done

if [ $drift -ne 0 ]; then
  echo
  echo "K8s version drift detected. Bump KUBERNETES_VERSION in clusterclass-tuist.yaml AND topology.version in every Cluster CR together." >&2
  exit 1
fi

echo "OK: ClusterClass and all per-env Cluster CRs agree on K8s $CC_VERSION"
