#!/usr/bin/env bash
# mise description="Creates Tuist iOS app .ipa archive and uploads it to App Store Connect."

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
    --username "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD"

echo "Upload to App Store Connect completed successfully!"
