#!/usr/bin/env bash
#MISE description "Provision a new Scaleway Mac mini for xcode_processor"
#MISE raw=true
#USAGE arg "<name>" help="Server name (e.g. xcode-processor-paris-1)"
#USAGE option "-t --type" help="Server type" default="M2-L"
#USAGE option "--zone" help="Scaleway zone" default="fr-par-3"
#USAGE option "--ip" help="IP of an existing machine (skip creation)"
#USAGE option "--sudo-password" help="Sudo password for existing machine"
set -euo pipefail

cd "$(dirname "$0")/../.."

SERVER_NAME="${usage_name?}"
SERVER_TYPE="${usage_type:-M2-L}"
ZONE="${usage_zone:-fr-par-3}"

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/xcode-processor}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
if [ -f "${SSH_KEY}" ]; then
    SSH_OPTS="${SSH_OPTS} -o IdentitiesOnly=yes -i ${SSH_KEY}"
fi

if [ -n "${usage_ip:-}" ]; then
    SERVER_IP="${usage_ip}"
    SUDO_PASSWORD="${usage_sudo_password:?--sudo-password required when --ip is set}"
    SSH_USER="${SSH_USER:-m1}"
    echo "==> Using existing machine at ${SERVER_IP}"
else
    echo "==> Creating Scaleway Mac mini '${SERVER_NAME}' (${SERVER_TYPE}) in ${ZONE}..."
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
fi

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
scp ${SSH_OPTS} platform/bootstrap.sh "${SSH_USER}@${SERVER_IP}:/tmp/bootstrap.sh"
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "chmod +x /tmp/bootstrap.sh && /tmp/bootstrap.sh ${SERVER_NAME} && rm /tmp/bootstrap.sh"

echo ""
echo "==> Provisioning complete!"
echo "    Host: ${SERVER_IP}"
echo "    SSH:  ssh ${SSH_OPTS} ${SSH_USER}@${SERVER_IP}"
echo ""
echo "Next steps:"
echo "  1. Add the age public key (printed above) to platform/.sops.yaml"
echo "  2. Re-encrypt secrets: cd platform && sops updatekeys secrets.yaml"
echo "  3. Add host config: platform/hosts/${SERVER_NAME}.nix"
echo "  4. Add DNS record: ${SERVER_NAME}.tuist.dev -> ${SERVER_IP}"
echo "  5. Store SSH key + host in 1Password"
echo "  6. Apply nix-darwin: mise run darwin-apply ${SERVER_IP} ${SERVER_NAME}"
echo "  7. Deploy: mise run deploy ${SERVER_IP} staging"
