#!/usr/bin/env bash
#MISE description="Provision a Scaleway Mac mini as a dedicated VM image builder (no Orchard)"
#MISE raw=true
#USAGE arg "<name>" help="Hostname for the machine (e.g. vm-image-builder-01)"
#USAGE arg "[runner_version]" help="GitHub Actions runner version (default: 2.333.1)"
#USAGE option "-t --type" help="Server type" default="M2-L"
#USAGE option "--zone" help="Scaleway zone" default="fr-par-3"
#USAGE option "--os" help="macOS version to install" default="macos-tahoe-26.0"
#USAGE option "--ip" help="IP of an existing machine (skip creation)"
#USAGE option "--sudo-password" help="Sudo password for existing machine"
#USAGE option "--github-url" help="GitHub URL to register runner with" default="https://github.com/tuist"
#
# This machine's sole purpose is building Tart VM images via Packer.
# It is NOT part of the Orchard cluster and does NOT run user workloads.
#
# The GitHub Actions runner registration token must be provided via the
# GITHUB_RUNNER_TOKEN environment variable. Generate one at:
#   https://github.com/organizations/tuist/settings/actions/runners/new

set -euo pipefail

SERVER_NAME="${usage_name?}"
SERVER_TYPE="${usage_type:-M2-L}"
ZONE="${usage_zone:-fr-par-3}"
OS="${usage_os:-macos-tahoe-26.0}"
RUNNER_VERSION="${usage_runner_version:-2.333.1}"
GITHUB_URL="${usage_github_url:-https://github.com/tuist}"
RUNNER_LABELS="self-hosted,macos,bare-metal,vm-image-builder"

if [ -z "${GITHUB_RUNNER_TOKEN:-}" ]; then
    echo "ERROR: GITHUB_RUNNER_TOKEN environment variable is required."
    echo "Generate a registration token at:"
    echo "  https://github.com/organizations/tuist/settings/actions/runners/new"
    exit 1
fi

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/scaleway}"
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

    echo "    IP:   ${SERVER_IP}"
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

ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "sudo -n true" || {
    echo "ERROR: passwordless sudo verification failed"
    exit 1
}

echo "==> Installing Homebrew, Tart, and Packer..."
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" bash <<'REMOTE'
set -euo pipefail

if ! command -v brew &>/dev/null; then
    echo "    Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "    Homebrew already installed."
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! command -v tart &>/dev/null; then
    echo "    Installing Tart..."
    brew install cirruslabs/cli/tart
else
    echo "    Tart already installed."
fi

if ! command -v packer &>/dev/null; then
    echo "    Installing Packer..."
    brew install hashicorp/tap/packer
else
    echo "    Packer already installed."
fi
REMOTE

echo "==> Installing GitHub Actions runner (v${RUNNER_VERSION})..."
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" bash <<REMOTE
set -euo pipefail

RUNNER_DIR="/Users/${SSH_USER}/actions-runner"

if [ -d "\${RUNNER_DIR}" ] && [ -f "\${RUNNER_DIR}/.runner" ]; then
    echo "    Runner already configured. Skipping installation."
    echo "    To re-register, remove \${RUNNER_DIR} first."
    exit 0
fi

mkdir -p "\${RUNNER_DIR}"
cd "\${RUNNER_DIR}"

echo "    Downloading runner binary..."
curl -sL -o runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz"
tar xzf runner.tar.gz
rm runner.tar.gz

echo "    Registering runner with GitHub..."
./config.sh \
    --url "${GITHUB_URL}" \
    --token "${GITHUB_RUNNER_TOKEN}" \
    --name "${SERVER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --unattended \
    --replace

echo "    Installing runner as launchd service..."
sudo ./svc.sh install "${SSH_USER}"
sudo ./svc.sh start
REMOTE

echo ""
echo "==> Provisioning complete!"
echo "    Host:   ${SERVER_IP}"
echo "    Name:   ${SERVER_NAME}"
echo "    Labels: ${RUNNER_LABELS}"
echo ""
echo "Verify in GitHub:"
echo "  ${GITHUB_URL}/settings/actions/runners"
echo ""
echo "Target this runner in workflows with:"
echo "  runs-on: [self-hosted, macos, bare-metal, vm-image-builder]"
