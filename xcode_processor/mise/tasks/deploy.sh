#!/usr/bin/env bash
#MISE description "Deploy the Tuist server release to a Scaleway Mac mini in xcresult-processor mode"
#MISE raw=true
#USAGE arg "<host>" help="Target host (IP or hostname)"
#USAGE arg "<environment>" help="Target environment" {
#USAGE   choices "staging" "canary" "production"
#USAGE }
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

release_dir() {
    if [ -n "${TUIST_MIX_BUILD_ROOT:-}" ]; then
        printf '%s\n' "${TUIST_MIX_BUILD_ROOT}/server/prod/rel/tuist"
    else
        printf '%s\n' "${REPO_ROOT}/server/_build/prod/rel/tuist"
    fi
}

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

RELEASE_DIR="$(release_dir)"
TARBALL="tuist-xcresult-processor-${SHORT_SHA}.tar.gz"

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

sudo launchctl bootout system/org.nixos.dev.tuist.xcode-processor 2>/dev/null || true
echo "==> Stopped"
sleep 3

# Swap the symlink atomically
ln -sfn "\${RELEASE_PATH}" "\${CURRENT_LINK}"

# Write version metadata
echo "${GIT_SHA}" > "\${CURRENT_LINK}/.git_sha"

sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dev.tuist.xcode-processor.plist
echo "==> Started"

echo "==> Waiting for processor to claim the Oban heartbeat..."
# The release binds no HTTP port (TUIST_WEB=0). Liveness is proved by Oban
# updating its row in oban_peers within the first few seconds of boot. The
# launchd KeepAlive flag will kick a hung BEAM, so the practical health
# check here is "the launchd job is still running 30s after start".
HEALTHY=false
for i in \$(seq 1 30); do
    if sudo launchctl print system/org.nixos.dev.tuist.xcode-processor 2>/dev/null | grep -q "state = running"; then
        if [ \$i -ge 6 ]; then
            echo "==> Launchd job stable for \$((i * 2))s"
            HEALTHY=true
            break
        fi
    fi
    sleep 2
done

if [ "\${HEALTHY}" = "true" ]; then
    exit 0
fi

echo "ERROR: Launchd job not running after 60s"

# Rollback to previous release if available
if [ -n "\${PREVIOUS_RELEASE}" ] && [ -d "\${PREVIOUS_RELEASE}" ]; then
    echo "==> Rolling back to \${PREVIOUS_RELEASE}..."
    sudo launchctl bootout system/org.nixos.dev.tuist.xcode-processor 2>/dev/null || true
    sleep 3
    ln -sfn "\${PREVIOUS_RELEASE}" "\${CURRENT_LINK}"
    sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dev.tuist.xcode-processor.plist

    echo "==> Waiting for rollback launchd stability..."
    for i in \$(seq 1 15); do
        if sudo launchctl print system/org.nixos.dev.tuist.xcode-processor 2>/dev/null | grep -q "state = running"; then
            echo "==> Rollback stable"
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
                \"text\": \"Deployed *${SHORT_SHA}* to *xcresult-processor ${ENVIRONMENT}*\",
                \"footer\": \"Xcresult Processor Service\"
            }]
        }" > /dev/null
fi
