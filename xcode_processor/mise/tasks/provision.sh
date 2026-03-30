#!/usr/bin/env bash
#MISE description "Provision a new Scaleway Mac mini for xcode_processor"
#MISE raw=true
#USAGE arg "<name>" help="Hostname for the machine (e.g. xcode-processor-canary)"
#USAGE option "-t --type" help="Server type" default="M2-L"
#USAGE option "--zone" help="Scaleway zone" default="fr-par-3"
#USAGE option "--os" help="macOS version to install (use 'scw apple-silicon os list' to see options)" default="macos-tahoe-26.0"
#USAGE option "--ip" help="IP of an existing machine (skip creation)"
#USAGE option "--sudo-password" help="Sudo password for existing machine"
set -euo pipefail

cd "$(dirname "$0")/../.."

SERVER_NAME="${usage_name?}"
SERVER_TYPE="${usage_type:-M2-L}"
ZONE="${usage_zone:-fr-par-3}"
OS="${usage_os:-macos-tahoe-26.0}"

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
echo "==> Storing age key in 1Password..."
AGE_KEY=$(ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "sudo cat /var/lib/sops-nix/key.txt")
AGE_PUB=$(ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "export PATH=/nix/var/nix/profiles/default/bin:\$PATH && sudo nix shell nixpkgs#age -c age-keygen -y /var/lib/sops-nix/key.txt 2>/dev/null")
OP_TITLE="XCODE_PROCESSOR_AGE_KEY_${SERVER_NAME}"
op item create --vault cache --category "Secure Note" --title "${OP_TITLE}" "notesPlain=${AGE_KEY}" > /dev/null 2>&1 \
    && echo "    Stored as '${OP_TITLE}' in 1Password" \
    || echo "    WARNING: Failed to store age key in 1Password. Store manually."

echo ""
echo "==> Updating .sops.yaml and re-encrypting secrets..."
if grep -q "${AGE_PUB}" "platform/.sops.yaml" 2>/dev/null; then
    echo "    Age key already in .sops.yaml"
else
    # Extract existing keys, add new one, rewrite .sops.yaml
    EXISTING=$(grep -oE 'age1[a-z0-9]+' "platform/.sops.yaml" | sort -u)
    ALL_KEYS=$(echo -e "${EXISTING}\n${AGE_PUB}" | sort -u | paste -sd ',' -)

    cat > "platform/.sops.yaml" <<SOPSEOF
creation_rules:
  - path_regex: secrets\\.yaml\$
    age: >-
      ${ALL_KEYS}
SOPSEOF
    echo "    Added to .sops.yaml"
fi

# Re-encrypt so the new machine can decrypt
echo "${AGE_KEY}" > /tmp/age.key
(cd platform && SOPS_AGE_KEY_FILE=/tmp/age.key sops updatekeys secrets.yaml --yes 2>&1 | grep -v "^$" | head -5)
rm -f /tmp/age.key
echo "    Secrets re-encrypted for all machines"

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
echo "  1. Add host config: platform/hosts/${SERVER_NAME}.nix"
echo "  2. Add to platform/flake.nix darwinConfigurations"
echo "  3. Add DNS record: ${SERVER_NAME}.tuist.dev -> ${SERVER_IP}"
echo "  4. Commit and push"
echo "  5. Apply nix-darwin: mise run darwin-apply ${SERVER_IP} ${SERVER_NAME}"
echo "  6. Deploy: mise run deploy ${SERVER_IP} staging"
