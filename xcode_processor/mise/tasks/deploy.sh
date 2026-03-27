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

echo "==> Fetching secrets from 1Password..."
SECRETS=$(op read "op://cache/xcode-processor-${ENVIRONMENT}/env" 2>/dev/null || true)

echo "==> Building release..."
mise run build-release

RELEASE_DIR="_build/prod/rel/xcode_processor"
TARBALL="xcode_processor-${GIT_SHA:0:8}.tar.gz"

echo "==> Packaging release..."
tar -czf "$TARBALL" -C "$RELEASE_DIR" .

echo "==> Uploading to ${HOST}..."
ssh "${DEPLOY_USER}@${HOST}" "mkdir -p ${REMOTE_DIR}/releases/${GIT_SHA:0:8}"
scp "$TARBALL" "${DEPLOY_USER}@${HOST}:${REMOTE_DIR}/releases/${GIT_SHA:0:8}/release.tar.gz"

echo "==> Deploying on remote host..."
ssh "${DEPLOY_USER}@${HOST}" bash <<REMOTE
set -euo pipefail

RELEASE_PATH="${REMOTE_DIR}/releases/${GIT_SHA:0:8}"
CURRENT_LINK="${REMOTE_DIR}/current"

cd "\${RELEASE_PATH}"
tar -xzf release.tar.gz
rm release.tar.gz

# Stop the running service
sudo launchctl bootout system/io.tuist.xcode-processor 2>/dev/null || true

# Swap the symlink atomically
ln -sfn "\${RELEASE_PATH}" "\${CURRENT_LINK}"

# Write version metadata
echo "${GIT_SHA}" > "\${CURRENT_LINK}/.git_sha"

# Start the service
sudo launchctl bootstrap system /Library/LaunchDaemons/io.tuist.xcode-processor.plist

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
echo "==> Deployed ${GIT_SHA:0:8} to ${HOST}"

# Send Slack notification if webhook URL is available
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"attachments\": [{
                \"color\": \"good\",
                \"text\": \"Deployed *${GIT_SHA:0:8}* to *xcode-processor ${ENVIRONMENT}*\",
                \"footer\": \"Xcode Processor Service\"
            }]
        }" > /dev/null
fi
