#!/usr/bin/env bash
#MISE description "Apply nix-darwin configuration to a remote Mac mini"
#MISE raw=true
#USAGE arg "<host>" help="Target host (IP or hostname)"
#USAGE arg "<hostname>" help="nix-darwin hostname" {
#USAGE   choices "xcode-processor-production" "xcode-processor-canary" "xcode-processor-staging"
#USAGE }
set -euo pipefail

HOST="${usage_host?}"
HOSTNAME="${usage_hostname?}"
PLATFORM_DIR="platform"

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/xcode-processor}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
if [ -f "${SSH_KEY}" ]; then
    SSH_OPTS="${SSH_OPTS} -o IdentitiesOnly=yes -i ${SSH_KEY}"
fi

echo "==> Ensuring users exist on ${HOST}..."
ssh ${SSH_OPTS} "m1@${HOST}" bash <<'USERS'
# nix-darwin declares users but doesn't create them via sysadminctl
for user in xcode-processor github-actions; do
    if ! id -u "$user" &>/dev/null; then
        echo "    Creating user $user..."
        sudo sysadminctl -addUser "$user" -home "/Users/$user" -shell /bin/bash
    fi
done
USERS

echo "==> Copying platform config to ${HOST}..."
ssh ${SSH_OPTS} "m1@${HOST}" "rm -rf /tmp/xcode-processor-platform"
scp ${SSH_OPTS} -r "${PLATFORM_DIR}" "m1@${HOST}:/tmp/xcode-processor-platform"

echo "==> Applying nix-darwin config..."
ssh ${SSH_OPTS} "m1@${HOST}" bash <<REMOTE
set -euo pipefail
export PATH="/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:\$PATH"
cd /tmp/xcode-processor-platform

# Rename any conflicting /etc files from manual setup
for f in /etc/caddy/Caddyfile /etc/sudoers.d/xcode-processor-deploy; do
    if [ -f "\$f" ] && ! readlink "\$f" | grep -q nix; then
        sudo mv "\$f" "\$f.before-nix-darwin" 2>/dev/null || true
    fi
done

if command -v darwin-rebuild &>/dev/null; then
    sudo PATH="\$PATH" darwin-rebuild switch --flake ".#${HOSTNAME}"
else
    echo "    First run -- bootstrapping nix-darwin..."
    sudo PATH="\$PATH" nix run nix-darwin -- switch --flake ".#${HOSTNAME}"
fi
rm -rf /tmp/xcode-processor-platform
echo "==> Applied successfully"
REMOTE
