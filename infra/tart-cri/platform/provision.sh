#!/usr/bin/env bash
# Provisions a Scaleway Mac mini as a full-class Kubernetes node backed
# by tart-cri. End-to-end: orders the machine from Scaleway's Apple
# Silicon API, waits for SSH, sets up passwordless sudo + GUI auto-
# login (Tart requires a live console session for
# Virtualization.framework), installs Tart + kubelet + tart-cri +
# tart-cni, writes the kubelet config + bootstrap kubeconfig, and
# boots the daemons under launchd.
#
# Prereqs (run on your laptop):
#   - `scw` CLI configured (token in ~/.config/scw/config.yaml).
#   - 1Password CLI signed in.
#   - The cluster's kubeadm bootstrap token in 1Password
#     (op://tuist-k8s-<env>/KUBEADM_BOOTSTRAP_TOKEN/password) plus
#     KUBE_API_SERVER + KUBE_CA_HASH for the join.
#
# Usage:
#   # Order a fresh Scaleway machine + provision it:
#   ./provision.sh staging mac-mini-staging-01 10.42.1.0/24
#
#   # Re-provision an existing machine (skip Scaleway create):
#   SERVER_IP=51.x.y.z SUDO_PASSWORD=... ./provision.sh staging mac-mini-staging-01 10.42.1.0/24

set -euo pipefail

ENV="${1:?env required}"
HOSTNAME="${2:?hostname required}"
POD_CIDR="${3:?pod_cidr required}"

KUBELET_VERSION="${KUBELET_VERSION:-1.32.1}"
SCALEWAY_TYPE="${SCALEWAY_TYPE:-M2-M}"
SCALEWAY_ZONE="${SCALEWAY_ZONE:-fr-par-3}"
SCALEWAY_OS="${SCALEWAY_OS:-macos-tahoe-26.0}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/scaleway}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLATFORM_DIR="${REPO_ROOT}/infra/tart-cri/platform"

# === Step 1: Order the Scaleway Mac mini (or use an existing one) ============
#
# Scaleway's Apple Silicon API (`scw apple-silicon server create`) is
# imperative — there's no Cluster API provider for it today. We wait
# for the machine to power on and emit its IP + the one-time sudo
# password the OS comes pre-configured with.

if [ -z "${SERVER_IP:-}" ]; then
    echo "==> Resolving Scaleway OS ID for '${SCALEWAY_OS}'..."
    OS_ID=$(scw apple-silicon os list zone="${SCALEWAY_ZONE}" -o json \
        | jq -r ".[] | select(.name == \"${SCALEWAY_OS}\") | .id")
    if [ -z "${OS_ID}" ] || [ "${OS_ID}" = "null" ]; then
        echo "ERROR: OS '${SCALEWAY_OS}' not found in zone ${SCALEWAY_ZONE}. Available:"
        scw apple-silicon os list zone="${SCALEWAY_ZONE}" -o json | jq -r '.[].name'
        exit 1
    fi

    echo "==> Creating Scaleway Mac mini '${HOSTNAME}' (${SCALEWAY_TYPE}, ${SCALEWAY_OS}) in ${SCALEWAY_ZONE}..."
    SERVER_JSON=$(scw apple-silicon server create \
        name="${HOSTNAME}" \
        type="${SCALEWAY_TYPE}" \
        zone="${SCALEWAY_ZONE}" \
        os-id="${OS_ID}" \
        --wait \
        -o json)

    SERVER_IP=$(echo "${SERVER_JSON}" | jq -r '.ip')
    SUDO_PASSWORD=$(echo "${SERVER_JSON}" | jq -r '.sudo_password')
    SSH_USER=$(echo "${SERVER_JSON}" | jq -r '.ssh_username')
    SERVER_ID=$(echo "${SERVER_JSON}" | jq -r '.id')

    echo "    Created server ${SERVER_ID}"
    echo "    IP:   ${SERVER_IP}"
    echo "    User: ${SSH_USER}"

    # Stash the sudo password in 1Password so a future operator can
    # SSH back in for diagnostics. Apple's licensing means the
    # machine is rented for at least 24h, so this matters.
    op item create --vault "tuist-k8s-${ENV}" --category "Secure Note" \
        --title "SCALEWAY_${HOSTNAME}_SUDO" \
        "notesPlain=${SUDO_PASSWORD}" >/dev/null 2>&1 || \
        echo "    WARNING: Failed to stash sudo password in 1Password — note it manually: ${SUDO_PASSWORD}"
else
    : "${SUDO_PASSWORD:?SUDO_PASSWORD required when SERVER_IP is set}"
    SSH_USER="${SSH_USER:-m1}"
    echo "==> Using existing machine at ${SERVER_IP}"
fi

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o IdentitiesOnly=yes -i ${SSH_KEY}"

# === Step 2: Wait for SSH ====================================================
#
# Scaleway reports `ready` when the BMC console is up; SSH is usually
# available a few seconds later but we tolerate a few minutes.

echo "==> Waiting for SSH..."
for i in $(seq 1 60); do
    if ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${SERVER_IP}" "true" 2>/dev/null; then
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: SSH not available after 5 minutes"
        exit 1
    fi
    sleep 5
done

# === Step 3: Passwordless sudo ===============================================
#
# The provision flow needs sudo without prompting (homebrew install,
# launchctl bootstrap, /etc writes). We grant the SSH user
# NOPASSWD:ALL using their OS-default password once, then never need
# it again.

echo "==> Enabling passwordless sudo for ${SSH_USER}..."
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" \
    "echo '${SUDO_PASSWORD}' | sudo -S sh -c 'echo \"${SSH_USER} ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/${SSH_USER} && chmod 0440 /etc/sudoers.d/${SSH_USER}'"
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "sudo -n true" || {
    echo "ERROR: passwordless sudo verification failed"; exit 1;
}

# === Step 4: GUI auto-login (Tart requirement) ===============================
#
# Virtualization.framework needs the user to be logged in at the
# console — SSH sessions don't grant Secure Enclave / VM management
# access. We enable auto-login via /etc/kcpassword + the
# autoLoginUser default, then reboot once so the next boot lands in
# the GUI session.
#
# kcpassword's encoding is a fixed XOR with a magic key (Apple's
# "well-known plaintext" — same key Apple uses internally; documented
# at https://www.brock-family.org/gavin/perl/kcpassword.html).

echo "==> Enabling auto-login for ${SSH_USER}..."
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" \
    SUDO_PASSWORD="${SUDO_PASSWORD}" \
    SSH_USER="${SSH_USER}" \
    bash <<'AUTOLOGIN'
set -euo pipefail
KEY=(0x7D 0x89 0x52 0x23 0xD2 0xBC 0xDD 0xEA 0xA3 0xB9 0x1F)
encode() {
    local pw="$1" out=""
    for ((i=0; i<${#pw}; i++)); do
        local c=$(printf '%d' "'${pw:i:1}")
        local k=${KEY[$((i % ${#KEY[@]}))]}
        out+=$(printf '\\x%02x' $((c ^ k)))
    done
    # Pad to 12 bytes with the magic key itself (Apple convention).
    while [ $((${#pw} + (${#pw} == ${#KEY[@]} ? 1 : 0))) -lt 12 ]; do
        out+=$(printf '\\x%02x' "${KEY[$((${#pw} % ${#KEY[@]}))]}")
        pw="${pw}_"
    done
    printf "${out}"
}
encoded=$(encode "${SUDO_PASSWORD}")
printf '%b' "${encoded}" | sudo tee /etc/kcpassword > /dev/null
sudo chmod 600 /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser "${SSH_USER}"
AUTOLOGIN

# === Step 5: Build + ship the binaries =======================================

echo "==> Building tart-cri + tart-cni for darwin/arm64..."
(cd "${REPO_ROOT}/infra/tart-cri" && \
  GOOS=darwin GOARCH=arm64 go build -o /tmp/tart-cri ./cmd/tart-cri && \
  GOOS=darwin GOARCH=arm64 go build -o /tmp/tart-cni ./cmd/tart-cni)

echo "==> Reading cluster join material from 1Password..."
KUBEADM_TOKEN=$(op read "op://tuist-k8s-${ENV}/KUBEADM_BOOTSTRAP_TOKEN/password")
KUBE_API_SERVER=$(op read "op://tuist-k8s-${ENV}/KUBE_API_SERVER/password")
KUBE_CA_HASH=$(op read "op://tuist-k8s-${ENV}/KUBE_CA_HASH/password")

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
