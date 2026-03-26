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

xcrun altool --upload-app \
    --type ios \
    --file "build/Tuist.ipa" \
    --username "$(op read "op://tuist/App Specific Password/username")" \
    --password "$(op read "op://tuist/App Specific Password/password")"

echo "Upload to App Store Connect completed successfully!"
