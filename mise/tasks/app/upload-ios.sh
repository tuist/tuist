#!/usr/bin/env bash
#MISE description="Creates Tuist iOS app .ipa archive and uploads it to App Store Connect."

set -eo pipefail

# Run the bundle script first
echo "Building iOS app bundle..."
mise/tasks/app/bundle-ios.sh

# Check if the IPA was created successfully
if [ ! -f "build/Tuist.ipa" ]; then
    echo "Error: build/Tuist.ipa not found. Bundle process may have failed."
    exit 1
fi

echo "Uploading to App Store Connect..."

ALTOOL_LOG=$(mktemp)
trap 'rm -f "$ALTOOL_LOG"' EXIT

if xcrun altool --upload-app \
    --type ios \
    --file "build/Tuist.ipa" \
    --username "$(op read "op://tuist/App Specific Password/username")" \
    --password "$(op read "op://tuist/App Specific Password/password")" 2>&1 | tee "$ALTOOL_LOG"; then
    echo "Upload to App Store Connect completed successfully!"
    exit 0
fi

# 90186 (train closed) and 90062 (version not above the approved one) mean App Store
# Connect already approved this marketing version, so iOS has shipped it. This
# happens when an earlier run uploaded the version but another platform failed and
# the release was never tagged. Failing here would keep the tag from being created,
# so every later run would recompute the same version and fail again.
if grep -qE '\((90186|90062)\)' "$ALTOOL_LOG"; then
    echo "::warning::App Store Connect already approved this iOS version; skipping the iOS upload so the release can be tagged."
    exit 0
fi

exit 1
