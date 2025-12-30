#!/usr/bin/env bash
#MISE description="Bundles the Tuist macOS app for distribution"

set -euo pipefail

TMP_DIR=/private$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIR/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
BUILD_DIRECTORY=$MISE_PROJECT_ROOT/app/build
APP_DIRECTORY=$MISE_PROJECT_ROOT/app/app-binary
DERIVED_DATA_PATH=$BUILD_DIRECTORY/app/derived
BUILD_DIRECTORY_BINARY=$DERIVED_DATA_PATH/Build/Products/Release/Tuist.app
BUILD_ARTIFACTS_DIRECTORY=$BUILD_DIRECTORY/artifacts
BUILD_ZIP_PATH=$BUILD_ARTIFACTS_DIRECTORY/app.zip
SHASUMS256_FILE=$BUILD_ARTIFACTS_DIRECTORY/SHASUMS256.txt
SHASUMS512_FILE=$BUILD_ARTIFACTS_DIRECTORY/SHASUMS512.txt
TEAM_ID='U6LC622NKF'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${YELLOW}$1${NC}"
}

# Remove temporary directory on exit
trap "rm -rf $TMP_DIR" EXIT

# Codesign
print_status "Code signing the Tuist App..."
if [ "${CI:-}" = "true" ]; then
    print_status "Creating a new temporary keychain..."
    security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
    security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
    security default-keychain -s $KEYCHAIN_PATH
    security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
fi

op read "op://tuist/Developer ID Application Certificate/certificate.p12" --out-file $TMP_DIR/certificate.p12
print_status "Importing certificate to keychain..."
security import $TMP_DIR/certificate.p12 -P $(op read "op://tuist/Developer ID Application Certificate/password") -A

# Build
print_status "Building the Tuist App..."
tuist generate --no-binary-cache --no-open
xcodebuild clean build -workspace $MISE_PROJECT_ROOT/Tuist.xcworkspace -scheme TuistApp -configuration Release -destination generic/platform=macOS -derivedDataPath $DERIVED_DATA_PATH CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# Codesign the app
print_status "Signing the app..."
codesign --force --timestamp --options runtime --sign "Developer ID Application: Tuist GmbH (U6LC622NKF)" "$BUILD_DIRECTORY_BINARY/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign --force --timestamp --options runtime --sign "Developer ID Application: Tuist GmbH (U6LC622NKF)" "$BUILD_DIRECTORY_BINARY/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
codesign --force --timestamp --options runtime --sign "Developer ID Application: Tuist GmbH (U6LC622NKF)" "$BUILD_DIRECTORY_BINARY/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
codesign --force --timestamp --options runtime --sign "Developer ID Application: Tuist GmbH (U6LC622NKF)" "$BUILD_DIRECTORY_BINARY/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
codesign --force --deep --timestamp --options runtime --sign "Developer ID Application: Tuist GmbH (U6LC622NKF)" "$BUILD_DIRECTORY_BINARY"

# Notarize
print_status "Submitting the Tuist App for notarization..."
mkdir -p $BUILD_ARTIFACTS_DIRECTORY

BUILD_DMG_PATH=$BUILD_ARTIFACTS_DIRECTORY/Tuist.dmg

print_status "Creating DMG..."
create-dmg --background $MISE_PROJECT_ROOT/assets/dmg-background.png --hide-extension "Tuist.app" --icon "Tuist.app" 139 161 --icon-size 95 --window-size 605 363 --app-drop-link 467 161 --volname "Tuist App" "$BUILD_DMG_PATH" "$BUILD_DIRECTORY_BINARY"

codesign --force --timestamp --options runtime --sign "Developer ID Application: Tuist GmbH (U6LC622NKF)" --identifier "dev.tuist.app.tuist-app-dmg" "$BUILD_DMG_PATH"

xcrun notarytool submit "${BUILD_DMG_PATH}" \
    --wait \
    --apple-id "$(op read "op://tuist/App Specific Password/username")" \
    --team-id "$TEAM_ID" \
    --password "$(op read "op://tuist/App Specific Password/password")" \
    --output-format json | jq -r '.id'
xcrun stapler staple "${BUILD_DMG_PATH}"

# Generating shasums
print_status "Generating shasums..."
for file in "$BUILD_ARTIFACTS_DIRECTORY"/*; do
    if [ -f "$file" ] && [[ $(basename "$file") != SHASUMS* ]]; then
        shasum -a 256 "$file" | awk '{print $1 "  " FILENAME}' FILENAME=$(basename "$file") >> "$SHASUMS256_FILE"
        shasum -a 512 "$file" | awk '{print $1 "  " FILENAME}' FILENAME=$(basename "$file") >> "$SHASUMS512_FILE"
    fi
done
