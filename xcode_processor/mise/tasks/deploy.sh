#!/usr/bin/env bash
#MISE description "Deploy xcode_processor to a Scaleway Mac mini"
#MISE raw=true
#USAGE arg "<host>" help="Target host (IP or hostname)"
#USAGE arg "<environment>" help="Target environment" {
#USAGE   choices "production"
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
SSH_CMD="ssh -o IdentitiesOnly=yes -i ${SSH_KEY}"
SCP_CMD="scp -o IdentitiesOnly=yes -i ${SSH_KEY}"

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

cd "\${RELEASE_PATH}"
tar -xzf release.tar.gz
rm release.tar.gz

# Stop the running service (try launchd first, then direct kill)
if sudo launchctl bootout system/io.tuist.xcode-processor 2>/dev/null; then
    echo "==> Stopped via launchd"
else
    pkill -f "xcode_processor.*start" 2>/dev/null && echo "==> Stopped running process" || echo "==> No running process found"
fi
sleep 2

# Swap the symlink atomically
ln -sfn "\${RELEASE_PATH}" "\${CURRENT_LINK}"

# Write version metadata
echo "${GIT_SHA}" > "\${CURRENT_LINK}/.git_sha"

# Start the service
if [ -f /Library/LaunchDaemons/io.tuist.xcode-processor.plist ]; then
    sudo launchctl bootstrap system /Library/LaunchDaemons/io.tuist.xcode-processor.plist
    echo "==> Started via launchd"
else
    # Direct start when launchd isn't configured yet
    SECRET_KEY_BASE="\${SECRET_KEY_BASE:-production-secret-key-base-that-is-at-least-64-bytes-long-for-xcode-processor}" \
    PORT="\${PORT:-4003}" \
    S3_ENDPOINT="\${S3_ENDPOINT:-https://s3.example.com}" \
    S3_BUCKET="\${S3_BUCKET:-tuist}" \
    S3_ACCESS_KEY_ID="\${S3_ACCESS_KEY_ID:-placeholder}" \
    S3_SECRET_ACCESS_KEY="\${S3_SECRET_ACCESS_KEY:-placeholder}" \
    WEBHOOK_SECRET="\${WEBHOOK_SECRET:-dev-webhook-secret}" \
      "\${CURRENT_LINK}/bin/xcode_processor" daemon
    echo "==> Started directly (no launchd plist found)"
fi

echo "==> Waiting for health check..."
for i in \$(seq 1 30); do
    if curl -sf http://localhost:4003/health > /dev/null 2>&1; then
        echo "==> Health check passed!"
        exit 0
    fi
    sleep 2
done

echo "ERROR: Health check failed after 60s"
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
