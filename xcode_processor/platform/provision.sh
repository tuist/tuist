#!/bin/bash
# Provision a new Scaleway Mac mini for xcode_processor.
#
# This script:
#   1. Creates a Mac mini via Scaleway API
#   2. Waits for it to be ready
#   3. Enables passwordless sudo
#   4. Runs the bootstrap script
#
# Prerequisites:
#   - `scw` CLI installed and configured
#   - SSH key added to your Scaleway project
#
# Usage:
#   ./provision.sh [name] [type]
#   ./provision.sh xcode-processor-paris-1 M2-L
#
# To provision on an existing machine (skip creation):
#   SKIP_CREATE=1 SERVER_IP=1.2.3.4 SUDO_PASSWORD=xxx ./provision.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_NAME="${1:-xcode-processor-paris-1}"
SERVER_TYPE="${2:-M2-L}"
ZONE="${ZONE:-fr-par-3}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/xcode-processor}"

if [ "${SKIP_CREATE:-}" != "1" ]; then
    echo "==> Creating Scaleway Mac mini '${SERVER_NAME}' (${SERVER_TYPE})..."
    SERVER_JSON=$(scw apple-silicon server create \
        name="${SERVER_NAME}" \
        type="${SERVER_TYPE}" \
        zone="${ZONE}" \
        --wait \
        -o json)

    SERVER_IP=$(echo "$SERVER_JSON" | jq -r '.ip')
    SUDO_PASSWORD=$(echo "$SERVER_JSON" | jq -r '.sudo_password')
    SSH_USER=$(echo "$SERVER_JSON" | jq -r '.ssh_username')

    echo "    IP: ${SERVER_IP}"
    echo "    User: ${SSH_USER}"
    echo "    Sudo password retrieved from API"
else
    SERVER_IP="${SERVER_IP:?SERVER_IP required when SKIP_CREATE=1}"
    SUDO_PASSWORD="${SUDO_PASSWORD:?SUDO_PASSWORD required when SKIP_CREATE=1}"
    SSH_USER="${SSH_USER:-m1}"
    echo "==> Using existing machine at ${SERVER_IP}"
fi

SSH_OPTS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -i ${SSH_KEY}"

echo "==> Waiting for SSH to become available..."
for i in $(seq 1 60); do
    if ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${SERVER_IP}" "true" 2>/dev/null; then
        echo "    SSH ready."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: SSH not available after 5 minutes"
        exit 1
    fi
    sleep 5
done

echo "==> Enabling passwordless sudo..."
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" \
    "echo '${SUDO_PASSWORD}' | sudo -S sh -c 'echo \"${SSH_USER} ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/${SSH_USER} && chmod 0440 /etc/sudoers.d/${SSH_USER}'"

echo "==> Verifying passwordless sudo..."
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "sudo -n echo 'passwordless sudo works'"

echo "==> Running bootstrap..."
# TODO: change to main branch once merged
BOOTSTRAP_URL="https://raw.githubusercontent.com/tuist/tuist/feat/xcode-processor/xcode_processor/platform/bootstrap.sh"
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "curl -fsSL ${BOOTSTRAP_URL} | bash"

echo ""
echo "==> Provisioning complete!"
echo "    Host: ${SERVER_IP}"
echo "    SSH:  ssh -o IdentitiesOnly=yes -i ${SSH_KEY} ${SSH_USER}@${SERVER_IP}"
