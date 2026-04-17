#!/usr/bin/env bash
#MISE description "Provision a Scaleway Mac mini as a dedicated VM image builder (no Orchard)"
#MISE raw=true
#USAGE arg "<name>" help="Hostname for the machine (e.g. vm-image-builder-01)"
#
# This machine's sole purpose is building Tart VM images via Packer.
# It is NOT part of the Orchard cluster and does NOT run user workloads.
#
# The GitHub Actions runner registration token is read from 1Password:
#   op://cache/GITHUB_ACTIONS_VM_IMAGE_BUILDER_TOKEN/notesPlain

set -euo pipefail

SERVER_NAME="${usage_name?}"
SERVER_TYPE="${SERVER_TYPE:-M1-M}"
ZONE="${ZONE:-fr-par-3}"
OS="${OS:-macos-tahoe-26.0}"
RUNNER_VERSION="${RUNNER_VERSION:-2.333.1}"
GITHUB_URL="${GITHUB_URL:-https://github.com/tuist}"
RUNNER_LABELS="self-hosted,macos,bare-metal,vm-image-builder"

echo "==> Reading GitHub Actions runner token from 1Password..."
if ! command -v op &>/dev/null; then
    echo "ERROR: 1Password CLI (op) is not installed. Install with: brew install 1password-cli"
    exit 1
fi

GITHUB_RUNNER_TOKEN=$(op read "op://cache/GITHUB_ACTIONS_VM_IMAGE_BUILDER_TOKEN/notesPlain" 2>/dev/null || true)
if [ -z "${GITHUB_RUNNER_TOKEN}" ]; then
    echo "ERROR: Could not read GITHUB_ACTIONS_VM_IMAGE_BUILDER_TOKEN from 1Password."
    echo "Ensure the item exists in the 'cache' vault and you are signed in to 1Password."
    exit 1
fi

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/scaleway}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
if [ -f "${SSH_KEY}" ]; then
    SSH_OPTS="${SSH_OPTS} -o IdentitiesOnly=yes -i ${SSH_KEY}"
fi

if [ -n "${SERVER_IP:-}" ]; then
    SUDO_PASSWORD="${SUDO_PASSWORD:?SUDO_PASSWORD required when SERVER_IP is set}"
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

echo "    Installing runner as LaunchDaemon..."
sudo tee /Library/LaunchDaemons/actions.runner.tuist.${SERVER_NAME}.plist > /dev/null <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>actions.runner.tuist.${SERVER_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>\${RUNNER_DIR}/runsvc.sh</string>
    </array>
    <key>UserName</key>
    <string>${SSH_USER}</string>
    <key>WorkingDirectory</key>
    <string>\${RUNNER_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/${SSH_USER}/Library/Logs/actions.runner.tuist.${SERVER_NAME}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/${SSH_USER}/Library/Logs/actions.runner.tuist.${SERVER_NAME}/stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
PLISTEOF

mkdir -p /Users/${SSH_USER}/Library/Logs/actions.runner.tuist.${SERVER_NAME}
sudo launchctl load /Library/LaunchDaemons/actions.runner.tuist.${SERVER_NAME}.plist
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
