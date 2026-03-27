#!/bin/bash
# Bootstrap a fresh Scaleway Mac mini for xcode_processor.
#
# Run this ON the Mac mini after cloning the repo:
#   git clone https://github.com/tuist/tuist.git
#   cd tuist/xcode_processor/platform
#   ./bootstrap.sh
#
# Prerequisites:
#   - SSH access to the machine as an admin user
#   - Internet access

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOSTNAME="${1:-xcode-processor-paris-1}"

echo "==> [1/8] Installing Nix..."
if ! command -v nix &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
    # Source nix in current shell
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
    echo "    Nix already installed, skipping."
fi

echo "==> [2/8] Creating xcode-processor service user..."
if ! id -u xcode-processor &>/dev/null; then
    sudo sysadminctl -addUser xcode-processor -home /Users/xcode-processor -shell /bin/zsh -admin
else
    echo "    User xcode-processor already exists, skipping."
fi

echo "==> [3/8] Creating github-actions deploy user..."
if ! id -u github-actions &>/dev/null; then
    sudo sysadminctl -addUser github-actions -home /Users/github-actions -shell /bin/bash
else
    echo "    User github-actions already exists, skipping."
fi

echo "==> [4/8] Setting up deploy directory structure..."
sudo mkdir -p /Users/xcode-processor/xcode_processor/releases
sudo chown -R xcode-processor:staff /Users/xcode-processor/xcode_processor

echo "==> [5/8] Configuring sudoers for github-actions..."
SUDOERS_FILE="/etc/sudoers.d/xcode-processor-deploy"
if [ ! -f "$SUDOERS_FILE" ]; then
    cat <<'SUDOERS' | sudo tee "$SUDOERS_FILE" > /dev/null
github-actions ALL=(ALL) NOPASSWD: /bin/launchctl bootout system/io.tuist.xcode-processor
github-actions ALL=(ALL) NOPASSWD: /bin/launchctl bootstrap system /Library/LaunchDaemons/io.tuist.xcode-processor.plist
github-actions ALL=(ALL) NOPASSWD: /bin/launchctl kickstart -k system/io.tuist.xcode-processor
SUDOERS
    sudo chmod 0440 "$SUDOERS_FILE"
    sudo visudo -cf "$SUDOERS_FILE"
else
    echo "    Sudoers already configured, skipping."
fi

echo "==> [6/8] Setting up sops-nix age key..."
AGE_KEY_DIR="/var/lib/sops-nix"
AGE_KEY_FILE="${AGE_KEY_DIR}/key.txt"
if [ ! -f "$AGE_KEY_FILE" ]; then
    sudo mkdir -p "$AGE_KEY_DIR"
    sudo nix shell nixpkgs#age -c age-keygen -o "$AGE_KEY_FILE" 2>&1 | tee /dev/stderr
    sudo chmod 600 "$AGE_KEY_FILE"
    AGE_PUB=$(sudo nix shell nixpkgs#age -c age-keygen -y "$AGE_KEY_FILE")
    echo ""
    echo "    =================================================="
    echo "    AGE PUBLIC KEY (you'll need this in step 9):"
    echo "    ${AGE_PUB}"
    echo "    =================================================="
    echo ""
else
    AGE_PUB=$(sudo nix shell nixpkgs#age -c age-keygen -y "$AGE_KEY_FILE")
    echo "    Age key already exists."
    echo "    Public key: ${AGE_PUB}"
fi

echo "==> [7/8] Creating log directories..."
sudo mkdir -p /var/log/xcode-processor
sudo mkdir -p /var/log/grafana-alloy

echo "==> [8/8] Verifying Xcode installation..."
if xcrun --find xcresulttool &>/dev/null; then
    echo "    xcresulttool found: $(xcrun --find xcresulttool)"
    echo "    Xcode version: $(xcodebuild -version 2>/dev/null | head -1 || echo 'unknown')"
else
    echo ""
    echo "    WARNING: xcresulttool not found!"
    echo "    You need Xcode installed before the service can process xcresults."
    echo "    Options:"
    echo "      1. Install from App Store (needs Apple ID)"
    echo "      2. brew install xcodes && xcodes install --latest"
    echo "      3. Download .xip from developer.apple.com"
    echo "    Then: sudo xcode-select -s /Applications/Xcode.app"
    echo ""
fi

echo ""
echo "========================================"
echo "  Bootstrap complete!"
echo "========================================"
echo ""
echo "Now do the following (on your laptop, not on this machine):"
echo ""
echo "  1. Update xcode_processor/platform/.sops.yaml with the age public key:"
echo "       ${AGE_PUB:-<see above>}"
echo ""
echo "  2. Create and encrypt secrets:"
echo "       cd xcode_processor/platform"
echo "       sops secrets.yaml"
echo "     (Fill in: secret_key_base, webhook_secret, s3_endpoint, s3_bucket,"
echo "      s3_access_key_id, s3_secret_access_key, and grafana secrets)"
echo ""
echo "  3. Push the updated .sops.yaml and secrets.yaml to the repo"
echo ""
echo "  4. Back on this machine, apply nix-darwin config:"
echo "       cd tuist/xcode_processor/platform"
echo "       git pull"
echo "       darwin-rebuild switch --flake .#${HOSTNAME}"
echo ""
echo "  5. Set up SSH authorized_keys for github-actions:"
echo "       sudo mkdir -p /Users/github-actions/.ssh"
echo "       echo '<DEPLOY_PUBLIC_KEY>' | sudo tee /Users/github-actions/.ssh/authorized_keys"
echo "       sudo chown -R github-actions:staff /Users/github-actions/.ssh"
echo "       sudo chmod 700 /Users/github-actions/.ssh"
echo "       sudo chmod 600 /Users/github-actions/.ssh/authorized_keys"
echo ""
echo "  6. Add GitHub Actions secrets:"
echo "       - XCODE_PROCESSOR_SSH_PRIVATE_KEY (matching the public key above)"
echo "       - XCODE_PROCESSOR_OP_SERVICE_ACCOUNT_TOKEN"
echo "       - SLACK_WEBHOOK_URL"
echo ""
echo "  7. Test the deploy from your laptop:"
echo "       cd xcode_processor && mise run deploy production"
