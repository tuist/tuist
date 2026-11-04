#!/usr/bin/env bash
#MISE description="Assert the ClusterClass's KUBERNETES_VERSION pin, its version-gated package patches and every per-env Cluster CR agree"

# The ClusterClass pins kubelet/kubeadm/kubectl via apt
# (KUBERNETES_VERSION in preKubeadmCommands). The per-env Cluster CRs
# pin what KCP renders into the static pod manifests
# (topology.version). A Cluster may run a newer version than the pin
# while it upgrades ahead of the others: the
# *KubernetesPackages patches reinstall the packages at the Cluster's
# version whenever it differs from the pin. So:
#
#   - both KUBERNETES_VERSION exports (control plane and workers) match,
#   - both patches' enabledIf gates name the pin, and
#   - no Cluster runs older than the pin, since a new node would then
#     install a kubelet newer than its control plane.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CC="$REPO_ROOT/infra/k8s/clusters/clusterclass-tuist.yaml"

pins=$(grep -E '^\s+- export KUBERNETES_VERSION=' "$CC" \
  | sed -E 's/.*KUBERNETES_VERSION=v?//' \
  | tr -d ' ' \
  | sort -u)
if [ -z "$pins" ]; then
  echo "ERROR: could not parse KUBERNETES_VERSION from $CC" >&2
  exit 2
fi
if [ "$(echo "$pins" | wc -l)" -ne 1 ]; then
  echo "ERROR: clusterclass-tuist.yaml pins different KUBERNETES_VERSIONs: $(echo "$pins" | tr '\n' ' ')" >&2
  exit 1
fi
CC_VERSION="$pins"

drift=0

gates=$(grep -E "enabledIf: .*builtin\.(controlPlane|machineDeployment)\.version" "$CC" \
  | sed -E 's/.*"v([0-9.]+)".*/\1/')
if [ "$(echo "$gates" | grep -c .)" -ne 2 ]; then
  echo "ERROR: expected the two *KubernetesPackages enabledIf gates in clusterclass-tuist.yaml" >&2
  exit 2
fi
for gate in $gates; do
  if [ "$gate" != "$CC_VERSION" ]; then
    echo "DRIFT: a *KubernetesPackages enabledIf gate names v$gate but KUBERNETES_VERSION=$CC_VERSION"
    drift=1
  fi
done

# Both layouts: the flat CRs still applied by mgmt-cluster-apply.yml
# (preview, pentest) AND the Flux-reconciled ones under workloads/.
for f in "$REPO_ROOT"/infra/k8s/clusters/cluster-*.yaml \
         "$REPO_ROOT"/infra/k8s/clusters/workloads/*/cluster.yaml; do
  [ -e "$f" ] || continue
  topo=$(grep -E '^\s+version:\s+v?[0-9]+\.[0-9]+\.[0-9]+' "$f" \
    | head -1 \
    | awk '{print $2}' \
    | sed 's/^v//')
  name=${f#"$REPO_ROOT"/infra/k8s/clusters/}
  if [ -z "$topo" ]; then
    echo "WARN: $name has no topology.version line" >&2
    continue
  fi
  if [ "$topo" = "$CC_VERSION" ]; then
    continue
  fi
  if [ "$(printf '%s\n%s\n' "$CC_VERSION" "$topo" | sort -V | head -1)" != "$CC_VERSION" ]; then
    echo "DRIFT: $name: topology.version=$topo is older than the ClusterClass pin KUBERNETES_VERSION=$CC_VERSION"
    drift=1
  else
    echo "AHEAD: $name: topology.version=$topo (packages installed by the *KubernetesPackages patches)"
  fi
done

if [ $drift -ne 0 ]; then
  echo
  echo "K8s version drift detected. See the *KubernetesPackages patches in clusterclass-tuist.yaml." >&2
  exit 1
fi

echo "OK: ClusterClass pin and gates agree on K8s $CC_VERSION; no Cluster CR is older"
