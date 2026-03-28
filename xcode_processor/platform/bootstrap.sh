#!/bin/bash
# Minimal bootstrap for a fresh Scaleway Mac mini.
#
# This only installs the prerequisites needed before nix-darwin can run:
#   1. Nix (via Determinate installer)
#   2. Age key for sops-nix secret decryption
#
# Everything else (users, directories, services, sudoers, OpenSSL) is
# managed declaratively by nix-darwin via `mise run darwin-apply`.

set -euo pipefail

HOSTNAME="${1:-xcode-processor-paris-1}"

echo "==> [1/2] Installing Nix..."
if ! command -v nix &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
    echo "    Nix already installed, skipping."
fi

echo "==> [2/2] Setting up sops-nix age key..."
AGE_KEY_DIR="/var/lib/sops-nix"
AGE_KEY_FILE="${AGE_KEY_DIR}/key.txt"
if [ ! -f "$AGE_KEY_FILE" ]; then
    sudo mkdir -p "$AGE_KEY_DIR"
    sudo nix shell nixpkgs#age -c age-keygen -o "$AGE_KEY_FILE" 2>&1 | tee /dev/stderr
    sudo chmod 600 "$AGE_KEY_FILE"
    AGE_PUB=$(sudo nix shell nixpkgs#age -c age-keygen -y "$AGE_KEY_FILE")
    echo ""
    echo "    =================================================="
    echo "    AGE PUBLIC KEY (add to platform/.sops.yaml):"
    echo "    ${AGE_PUB}"
    echo "    =================================================="
    echo ""
else
    AGE_PUB=$(sudo nix shell nixpkgs#age -c age-keygen -y "$AGE_KEY_FILE")
    echo "    Age key already exists."
    echo "    Public key: ${AGE_PUB}"
fi

echo ""
echo "==> Bootstrap complete!"
echo ""
echo "Next: add the age public key to .sops.yaml, then run:"
echo "  mise run darwin-apply <ip> ${HOSTNAME}"
