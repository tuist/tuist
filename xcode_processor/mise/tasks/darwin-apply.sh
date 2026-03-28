#!/usr/bin/env bash
#MISE description "Apply nix-darwin configuration to a remote Mac mini"
#MISE raw=true
#USAGE arg "<host>" help="Target host (IP or hostname)"
#USAGE arg "<hostname>" help="nix-darwin hostname" {
#USAGE   choices "xcode-processor-paris-1"
#USAGE }
set -euo pipefail

HOST="${usage_host?}"
HOSTNAME="${usage_hostname?}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="${SCRIPT_DIR}/../../platform"

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/xcode-processor}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
if [ -f "${SSH_KEY}" ]; then
    SSH_OPTS="${SSH_OPTS} -o IdentitiesOnly=yes -i ${SSH_KEY}"
fi

echo "==> Copying platform config to ${HOST}..."
scp ${SSH_OPTS} -r "${PLATFORM_DIR}" "m1@${HOST}:/tmp/xcode-processor-platform"

echo "==> Applying nix-darwin config..."
ssh ${SSH_OPTS} "m1@${HOST}" bash <<REMOTE
set -euo pipefail
cd /tmp/xcode-processor-platform
darwin-rebuild switch --flake ".#${HOSTNAME}"
rm -rf /tmp/xcode-processor-platform
echo "==> Applied successfully"
REMOTE
