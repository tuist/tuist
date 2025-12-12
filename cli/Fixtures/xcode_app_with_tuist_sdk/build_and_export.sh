#!/bin/bash
set -e

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

ARCHIVE_PATH="$TEMP_DIR/App.xcarchive"
EXPORT_PATH="."
PROJECT="App.xcodeproj"
SCHEME="App"
CONFIGURATION="Release"
EXPORT_OPTIONS="ExportOptions.plist"

echo "📦 Archiving $SCHEME..."
xcodebuild archive \
    -archivePath "$ARCHIVE_PATH" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    | xcbeautify

echo "📤 Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates

echo "✅ Build and export completed successfully!"
