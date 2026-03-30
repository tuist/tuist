#!/usr/bin/env bash
#MISE description "Deploy xcode_processor to a Scaleway Mac mini"
#MISE raw=true
#USAGE arg "<host>" help="Target host (IP or hostname)"
#USAGE arg "<environment>" help="Target environment" {
#USAGE   choices "staging" "production"
#USAGE }
set -euo pipefail

cd "$(dirname "$0")/../.."

HOST="${usage_host?}"
ENVIRONMENT="${usage_environment?}"
DEPLOY_USER="github-actions"
REMOTE_DIR="/Users/xcode-processor/xcode_processor"
GIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
SHORT_SHA="${GIT_SHA:0:8}"

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/xcode-processor}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
if [ -f "${SSH_KEY}" ]; then
    SSH_OPTS="${SSH_OPTS} -o IdentitiesOnly=yes -i ${SSH_KEY}"
fi
SSH_CMD="ssh ${SSH_OPTS}"
SCP_CMD="scp ${SSH_OPTS}"

echo "==> Building release..."
mise run build-release

RELEASE_DIR="_build/prod/rel/xcode_processor"
TARBALL="xcode_processor-${SHORT_SHA}.tar.gz"

echo "==> Packaging release..."
tar -czf "$TARBALL" -C "$RELEASE_DIR" .

echo "==> Uploading to ${HOST}..."
${SSH_CMD} "${DEPLOY_USER}@${HOST}" "mkdir -p ${REMOTE_DIR}/releases/${SHORT_SHA}"
${SCP_CMD} "$TARBALL" "${DEPLOY_USER}@${HOST}:${REMOTE_DIR}/releases/${SHORT_SHA}/release.tar.gz"

echo "==> Deploying on remote host..."
${SSH_CMD} "${DEPLOY_USER}@${HOST}" bash <<REMOTE
set -euo pipefail

RELEASE_PATH="${REMOTE_DIR}/releases/${SHORT_SHA}"
CURRENT_LINK="${REMOTE_DIR}/current"

# Save previous release for rollback
PREVIOUS_RELEASE=""
if [ -L "\${CURRENT_LINK}" ]; then
    PREVIOUS_RELEASE=\$(readlink "\${CURRENT_LINK}")
    echo "==> Previous release: \${PREVIOUS_RELEASE}"
fi

cd "\${RELEASE_PATH}"
tar -xzf release.tar.gz
rm release.tar.gz

# Stop the running service (try launchd first, then direct kill)
if sudo launchctl bootout system/org.nixos.dev.tuist.xcode-processor 2>/dev/null; then
    echo "==> Stopped via launchd"
else
    pkill -f "xcode_processor.*start" 2>/dev/null && echo "==> Stopped running process" || echo "==> No running process found"
fi
sleep 2

# Swap the symlink atomically
ln -sfn "\${RELEASE_PATH}" "\${CURRENT_LINK}"

# Write version metadata
echo "${GIT_SHA}" > "\${CURRENT_LINK}/.git_sha"

start_service() {
    if [ -f /Library/LaunchDaemons/org.nixos.dev.tuist.xcode-processor.plist ]; then
        sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dev.tuist.xcode-processor.plist
        echo "==> Started via launchd"
    else
        # Direct start when launchd/sops-nix isn't configured yet -- read from .env
        ENV_FILE="${REMOTE_DIR}/.env"
        if [ -f "\${ENV_FILE}" ]; then
            set -a
            source "\${ENV_FILE}"
            set +a
        fi
        "\${CURRENT_LINK}/bin/xcode_processor" daemon
        echo "==> Started directly (no launchd plist found)"
    fi
}

stop_service() {
    if sudo launchctl bootout system/org.nixos.dev.tuist.xcode-processor 2>/dev/null; then
        echo "==> Stopped via launchd"
    else
        pkill -f "xcode_processor.*start" 2>/dev/null || true
    fi
    sleep 2
}

# Start the service
start_service

echo "==> Waiting for health check..."
HEALTHY=false
for i in \$(seq 1 30); do
    if curl -sf http://localhost:4003/health > /dev/null 2>&1; then
        echo "==> Health check passed!"
        HEALTHY=true
        break
    fi
    sleep 2
done

if [ "\${HEALTHY}" = "true" ]; then
    exit 0
fi

echo "ERROR: Health check failed after 60s"

# Rollback to previous release if available
if [ -n "\${PREVIOUS_RELEASE}" ] && [ -d "\${PREVIOUS_RELEASE}" ]; then
    echo "==> Rolling back to \${PREVIOUS_RELEASE}..."
    stop_service
    ln -sfn "\${PREVIOUS_RELEASE}" "\${CURRENT_LINK}"
    start_service

    echo "==> Waiting for rollback health check..."
    for i in \$(seq 1 15); do
        if curl -sf http://localhost:4003/health > /dev/null 2>&1; then
            echo "==> Rollback health check passed"
            break
        fi
        sleep 2
    done
else
    echo "==> No previous release to rollback to"
fi

exit 1
REMOTE

rm -f "$TARBALL"
echo "==> Deployed ${SHORT_SHA} to ${HOST}"

# Send Slack notification if webhook URL is available
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"attachments\": [{
                \"color\": \"good\",
                \"text\": \"Deployed *${SHORT_SHA}* to *xcode-processor ${ENVIRONMENT}*\",
                \"footer\": \"Xcode Processor Service\"
            }]
        }" > /dev/null
fi
