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
#
# Tart needs a live GUI login session on macOS for Virtualization.framework
# to access the Secure Enclave. SSH sessions and LaunchDaemons don't qualify.
# So this script: (1) enables auto-login via /etc/kcpassword, (2) installs the
# GitHub Actions runner as a LaunchAgent, (3) reboots so m1 logs in at the GUI,
# and (4) waits for the runner to come back online.

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
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
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

wait_for_ssh() {
    local label="$1"
    local attempts="$2"
    echo "==> Waiting for SSH (${label})..."
    for i in $(seq 1 "$attempts"); do
        if ssh ${SSH_OPTS} -o ConnectTimeout=5 "${SSH_USER}@${SERVER_IP}" "true" 2>/dev/null; then
            echo "    SSH ready."
            return 0
        fi
        sleep 5
    done
    echo "ERROR: SSH not available after $((attempts * 5)) seconds (${label})"
    return 1
}

wait_for_ssh "initial" 60

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

if [ ! -f "\${RUNNER_DIR}/.runner" ]; then
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
else
    echo "    Runner already registered. Skipping binary download."
fi

echo "    Removing any legacy LaunchDaemon..."
if [ -f /Library/LaunchDaemons/actions.runner.tuist.${SERVER_NAME}.plist ]; then
    sudo launchctl unload /Library/LaunchDaemons/actions.runner.tuist.${SERVER_NAME}.plist 2>/dev/null || true
    sudo rm -f /Library/LaunchDaemons/actions.runner.tuist.${SERVER_NAME}.plist
fi

echo "    Installing runner LaunchAgent..."
mkdir -p /Users/${SSH_USER}/Library/LaunchAgents
mkdir -p /Users/${SSH_USER}/Library/Logs/actions.runner.tuist.${SERVER_NAME}
tee /Users/${SSH_USER}/Library/LaunchAgents/actions.runner.tuist.${SERVER_NAME}.plist > /dev/null <<PLISTEOF
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
REMOTE

echo "==> Enabling auto-login for ${SSH_USER}..."
# kcpassword stores the user's password XOR'd against a fixed key so macOS
# can log the user in at boot without a human at the keyboard. Required for
# Tart to get Secure Enclave access (see header comment).
ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" bash <<REMOTE
set -euo pipefail
echo '${SUDO_PASSWORD}' | sudo python3 -c '
import os, sys
KEY = bytes([0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F])
password = sys.stdin.read().strip().encode("utf-8")
padded_len = (len(password) // 12 + 1) * 12
padded = password + bytes(padded_len - len(password))
out = bytearray(len(padded))
for i, b in enumerate(padded):
    out[i] = b ^ KEY[i % len(KEY)]
with open("/etc/kcpassword", "wb") as f:
    f.write(out)
os.chmod("/etc/kcpassword", 0o600)
'
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser ${SSH_USER}
REMOTE

echo "==> Checking whether a reboot is needed..."
CURRENT_CONSOLE_USER=$(ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" 'stat -f "%Su" /dev/console' 2>/dev/null || echo "")
if [ "${CURRENT_CONSOLE_USER}" = "${SSH_USER}" ]; then
    echo "    ${SSH_USER} already has an active GUI session; skipping reboot."
else
    echo "    Console user is '${CURRENT_CONSOLE_USER}', rebooting so auto-login takes effect..."
    ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "nohup sudo shutdown -r now >/dev/null 2>&1 &" || true
    echo "    Sleeping 30s for shutdown to start..."
    sleep 30
    wait_for_ssh "post-reboot" 60

    echo "==> Waiting for ${SSH_USER} GUI session (auto-login)..."
    for i in $(seq 1 30); do
        console=$(ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" 'stat -f "%Su" /dev/console' 2>/dev/null || echo "")
        if [ "$console" = "${SSH_USER}" ]; then
            echo "    ${SSH_USER} logged in."
            break
        fi
        if [ "$i" -eq 30 ]; then
            echo "ERROR: auto-login did not take effect after 150s (console user: $console)"
            exit 1
        fi
        sleep 5
    done
fi

echo "==> Verifying runner is alive..."
for i in $(seq 1 30); do
    if ssh ${SSH_OPTS} "${SSH_USER}@${SERVER_IP}" "pgrep -f 'Runner.Listener run' >/dev/null" 2>/dev/null; then
        echo "    Runner.Listener is running."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "ERROR: Runner.Listener did not start after 150s"
        exit 1
    fi
    sleep 5
done

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
