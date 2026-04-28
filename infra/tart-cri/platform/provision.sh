#!/usr/bin/env bash
# Provisions a Scaleway Mac mini as a Kubernetes node backed by tart-cri.
#
# Prereqs (run on your laptop):
#   - 1Password CLI signed in
#   - SSH key at ~/.ssh/scaleway with passwordless sudo on the target
#   - The cluster's kubeadm bootstrap token in 1Password
#     (op://tuist-k8s-<env>/KUBEADM_BOOTSTRAP_TOKEN/password)
#
# Usage:
#   ./provision.sh <env> <hostname> <pod_cidr>
#   ./provision.sh staging mac-mini-staging-01 10.42.1.0/24

set -euo pipefail

ENV="${1:?env required}"
HOSTNAME="${2:?hostname required}"
POD_CIDR="${3:?pod_cidr required}"

KUBELET_VERSION="${KUBELET_VERSION:-1.32.1}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/scaleway}"
SSH_USER="${SSH_USER:-m1}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLATFORM_DIR="${REPO_ROOT}/infra/tart-cri/platform"

if [ -z "${SERVER_IP:-}" ]; then
    echo "ERROR: set SERVER_IP=<ip> in env"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i ${SSH_KEY}"

echo "==> Reading cluster bootstrap token from 1Password..."
KUBEADM_TOKEN=$(op read "op://tuist-k8s-${ENV}/KUBEADM_BOOTSTRAP_TOKEN/password")
KUBE_API_SERVER=$(op read "op://tuist-k8s-${ENV}/KUBE_API_SERVER/password")
KUBE_CA_HASH=$(op read "op://tuist-k8s-${ENV}/KUBE_CA_HASH/password")

echo "==> Building tart-cri + tart-cni for darwin/arm64..."
(cd "${REPO_ROOT}/infra/tart-cri" && \
  GOOS=darwin GOARCH=arm64 go build -o /tmp/tart-cri ./cmd/tart-cri && \
  GOOS=darwin GOARCH=arm64 go build -o /tmp/tart-cni ./cmd/tart-cni)

echo "==> Copying binaries + configs to ${SERVER_IP}..."
scp ${SSH_OPTS} /tmp/tart-cri /tmp/tart-cni "${SSH_USER}@${SERVER_IP}:/tmp/"
scp ${SSH_OPTS} \
    "${PLATFORM_DIR}/kubelet-config.yaml" \
    "${PLATFORM_DIR}/dev.tuist.tart-cri.plist" \
    "${PLATFORM_DIR}/dev.tuist.kubelet.plist" \
    "${PLATFORM_DIR}/cni.conflist.template" \
    "${SSH_USER}@${SERVER_IP}:/tmp/"

echo "==> Bootstrapping the host..."
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" \
    HOSTNAME="${HOSTNAME}" \
    POD_CIDR="${POD_CIDR}" \
    KUBELET_VERSION="${KUBELET_VERSION}" \
    KUBEADM_TOKEN="${KUBEADM_TOKEN}" \
    KUBE_API_SERVER="${KUBE_API_SERVER}" \
    KUBE_CA_HASH="${KUBE_CA_HASH}" \
    bash <<'REMOTE'
set -euo pipefail

# 1. Install Tart if missing.
if ! command -v tart &>/dev/null; then
    echo "==> Installing Tart..."
    if ! command -v brew &>/dev/null; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    brew install cirruslabs/cli/tart
fi

# 2. Install kubelet binary for darwin/arm64.
if [ ! -x /usr/local/bin/kubelet ]; then
    echo "==> Installing kubelet ${KUBELET_VERSION}..."
    curl -fsSLo /tmp/kubelet \
        "https://dl.k8s.io/release/v${KUBELET_VERSION}/bin/darwin/arm64/kubelet"
    sudo install -m 0755 /tmp/kubelet /usr/local/bin/kubelet
    rm /tmp/kubelet
fi

# 3. Install tart-cri + tart-cni.
sudo install -m 0755 /tmp/tart-cri /usr/local/bin/tart-cri
sudo install -m 0755 /tmp/tart-cni /opt/cni/bin/tart-cni 2>/dev/null || {
    sudo mkdir -p /opt/cni/bin
    sudo install -m 0755 /tmp/tart-cni /opt/cni/bin/tart-cni
}

# 4. Directory layout.
sudo mkdir -p \
    /etc/kubernetes \
    /etc/kubernetes/pki \
    /etc/cni/net.d \
    /var/lib/kubelet \
    /var/lib/tart-cri \
    /var/log/tart-cri \
    /var/log/kubelet \
    /var/log/pods \
    /var/run/tart-cri

sudo chown -R "$(whoami):staff" /var/log/tart-cri /var/log/kubelet /var/lib/tart-cri /var/run/tart-cri

# 5. CNI config with this host's pod CIDR.
sudo sed "s|REPLACE_ME|${POD_CIDR}|" /tmp/cni.conflist.template \
    | sudo tee /etc/cni/net.d/10-tart.conflist > /dev/null

# 6. kubelet config.
sudo install -m 0644 /tmp/kubelet-config.yaml /etc/kubernetes/kubelet-config.yaml

# 7. Bootstrap kubeconfig (one-time use; kubelet rotates to a node-
#    specific cert after first join).
cat <<KUBECONFIG | sudo tee /etc/kubernetes/bootstrap-kubelet.conf > /dev/null
apiVersion: v1
kind: Config
clusters:
  - name: tuist
    cluster:
      server: ${KUBE_API_SERVER}
      certificate-authority-data: ${KUBE_CA_HASH}
contexts:
  - name: bootstrap
    context:
      cluster: tuist
      user: bootstrap
current-context: bootstrap
users:
  - name: bootstrap
    user:
      token: ${KUBEADM_TOKEN}
KUBECONFIG

# 8. launchd plists.
sudo install -m 0644 /tmp/dev.tuist.tart-cri.plist /Library/LaunchDaemons/dev.tuist.tart-cri.plist
sudo install -m 0644 /tmp/dev.tuist.kubelet.plist /Library/LaunchDaemons/dev.tuist.kubelet.plist
sudo chown root:wheel \
    /Library/LaunchDaemons/dev.tuist.tart-cri.plist \
    /Library/LaunchDaemons/dev.tuist.kubelet.plist

# 9. Boot the daemons.
sudo launchctl bootout system/dev.tuist.tart-cri 2>/dev/null || true
sudo launchctl bootout system/dev.tuist.kubelet 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuist.tart-cri.plist
sleep 2
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuist.kubelet.plist

# Cleanup.
rm -f /tmp/tart-cri /tmp/tart-cni /tmp/kubelet-config.yaml \
      /tmp/dev.tuist.tart-cri.plist /tmp/dev.tuist.kubelet.plist \
      /tmp/cni.conflist.template

echo "==> Bootstrap complete on $(hostname)."
echo "    Verify with: kubectl get nodes -l kubernetes.io/os=darwin"
REMOTE

echo "==> Provisioned ${HOSTNAME} (${SERVER_IP}) into the ${ENV} cluster."
echo "    Run: kubectl get nodes -l kubernetes.io/os=darwin"
