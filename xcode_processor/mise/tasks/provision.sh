#!/usr/bin/env bash
#MISE description "Provision a new Scaleway Mac mini for xcode_processor"
#MISE raw=true
#USAGE arg "<name>" help="Hostname for the machine (e.g. xcode-processor-canary)"
#USAGE option "-t --type" help="Server type" default="M2-L"
#USAGE option "--zone" help="Scaleway zone" default="fr-par-3"
#USAGE option "--os" help="macOS version to install (use 'scw apple-silicon os list' to see options)" default="macos_sequoia_26.0"
#USAGE option "--ip" help="IP of an existing machine (skip creation)"
#USAGE option "--sudo-password" help="Sudo password for existing machine"
set -euo pipefail

cd "$(dirname "$0")/../.."

SERVER_NAME="${usage_name?}"
SERVER_TYPE="${usage_type:-M2-L}"
ZONE="${usage_zone:-fr-par-3}"
OS="${usage_os:-macos_sequoia_26.0}"

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
    # Resolve OS ID
    echo "==> Looking up OS ID for '${OS}'..."
    OS_ID=$(scw apple-silicon os list zone="${ZONE}" -o json | jq -r ".[] | select(.name == \"${OS}\") | .id")
    if [ -z "${OS_ID}" ] || [ "${OS_ID}" = "null" ]; then
        echo "ERROR: OS '${OS}' not found. Available options:"
        scw apple-silicon os list zone="${ZONE}" -o json | jq -r '.[].name'
        exit 1
    fi

    echo "==> Creating Scaleway Mac mini '${SERVER_NAME}' (${SERVER_TYPE}, ${OS}) in ${ZONE}..."
    SERVER_JSON=$(scw apple-silicon server create \
        name="${SERVER_NAME}" \
        type="${SERVER_TYPE}" \
        zone="${ZONE}" \
        os-id="${OS_ID}" \
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

echo "==> Installing Nix and generating age key..."
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" bash <<'REMOTE'
set -euo pipefail

# Install Nix
if ! command -v nix &> /dev/null; then
    echo "==> Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
    echo "    Nix already installed."
fi

# Generate age key for sops-nix
AGE_KEY_FILE="/var/lib/sops-nix/key.txt"
if [ ! -f "$AGE_KEY_FILE" ]; then
    echo "==> Generating age key..."
    sudo mkdir -p /var/lib/sops-nix
    sudo nix shell nixpkgs#age -c age-keygen -o "$AGE_KEY_FILE" 2>&1 | tee /dev/stderr
    sudo chmod 600 "$AGE_KEY_FILE"
fi

AGE_PUB=$(sudo nix shell nixpkgs#age -c age-keygen -y "$AGE_KEY_FILE")
echo ""
echo "=================================================="
echo "AGE PUBLIC KEY (add to platform/.sops.yaml):"
echo "${AGE_PUB}"
echo "=================================================="
REMOTE

echo ""
echo "==> Setting up SSH key for github-actions..."
DEPLOY_PUB_KEY=$(op read "op://cache/XCODE_PROCESSOR_SSH_PRIVATE_KEY/notesPlain" 2>/dev/null | ssh-keygen -y -f /dev/stdin 2>/dev/null || true)
if [ -n "${DEPLOY_PUB_KEY}" ]; then
    ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" bash <<SSHEOF
sudo mkdir -p /Users/github-actions/.ssh
echo "${DEPLOY_PUB_KEY}" | sudo tee /Users/github-actions/.ssh/authorized_keys > /dev/null
sudo chown -R github-actions:staff /Users/github-actions/.ssh 2>/dev/null || true
sudo chmod 700 /Users/github-actions/.ssh
sudo chmod 600 /Users/github-actions/.ssh/authorized_keys
if sudo dseditgroup -o read com.apple.access_ssh &>/dev/null; then
    sudo dseditgroup -o edit -a github-actions -t user com.apple.access_ssh 2>/dev/null || true
fi
echo "    SSH key configured for github-actions"
SSHEOF
else
    echo "    WARNING: Could not read SSH key from 1Password. Set up github-actions SSH manually."
fi

echo ""
echo "==> Provisioning complete!"
echo "    Host: ${SERVER_IP}"
echo "    Name: ${SERVER_NAME}"
echo ""
echo "Next steps:"
echo "  1. Add the age public key (printed above) to platform/.sops.yaml"
echo "  2. Re-encrypt secrets: SOPS_AGE_KEY_FILE=<key-from-existing-machine> sops updatekeys platform/secrets.yaml"
echo "  3. Add host config: platform/hosts/${SERVER_NAME}.nix"
echo "  4. Add to platform/flake.nix darwinConfigurations"
echo "  5. Add DNS record: ${SERVER_NAME}.tuist.dev -> ${SERVER_IP}"
echo "  6. Commit and push"
echo "  7. Apply nix-darwin: mise run darwin-apply ${SERVER_IP} ${SERVER_NAME}"
echo "  8. Deploy: mise run deploy ${SERVER_IP} staging"
