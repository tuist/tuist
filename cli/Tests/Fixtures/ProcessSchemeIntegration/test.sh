#!/bin/bash
set -euo pipefail

REPOSITORY_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
RESULT_DIR="$(mktemp -d)"
trap 'rm -rf "$RESULT_DIR"' EXIT

cd "$REPOSITORY_DIR"
xcodebuild build -workspace Tuist.xcworkspace -scheme TuistProcessSchemeIntegration \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    TUIST_PROCESS_TEST_OUTPUT="$RESULT_DIR"

# Xcode does not propagate post-action failures to its exit status. Require both
# the post-action and its orphaned worker to report successful command execution.
for ((attempt = 0; attempt < 200; attempt++)); do
    if [[ -f "$RESULT_DIR/post-action" && -f "$RESULT_DIR/worker" ]]; then
        echo "Scheme post-action and detached worker both ran xcrun successfully."
        exit 0
    fi
    if compgen -G "$RESULT_DIR/*.error" > /dev/null; then
        cat "$RESULT_DIR/"*.error >&2
        exit 1
    fi
    sleep 0.1
done

echo "Timed out waiting for the scheme post-action and detached worker." >&2
exit 1
