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

# create-dmg styles the DMG window by driving Finder from AppleScript, which
# macOS gates behind an Automation approval. That consent is answered from the
# session user's TCC database, so an unseeded one leaves the send waiting on a
# prompt no headless VM can answer until it gives up with "Finder got an error:
# AppleEvent timed out. (-1712)".
#
# The runner image seeds the system database (infra/runner-image/runner.pkr.hcl),
# which is not where this decision is read from. It cannot seed the per-user one
# either: the account is created during the image build and its session first
# opens when the VM boots, so at build time the database does not exist. GitHub's
# images carry these same rows in the user database, which is why the step worked
# before macOS jobs moved to this fleet.
#
# Seed it here instead, on the VM that is about to run create-dmg. Guarded to CI
# so a local bundle never touches a developer's own approvals.
if [ "${CI:-}" = "true" ]; then
    print_status "Approving scripted Finder automation..."
    SYSTEM_TCC_DB='/Library/Application Support/com.apple.TCC/TCC.db'
    USER_TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

    # tccd creates this database on the account's first consent decision, which
    # on a fresh VM may not have happened yet. An empty file would shadow the
    # real one, so give it the system database's schema.
    if [ ! -f "$USER_TCC_DB" ]; then
        sudo mkdir -p "$(dirname "$USER_TCC_DB")"
        sudo sqlite3 "$SYSTEM_TCC_DB" .schema | sudo sqlite3 "$USER_TCC_DB"
    fi

    # TCC attributes an event to the responsible process, which for a shell
    # pipeline is usually an ancestor rather than osascript itself, so the
    # shells are seeded alongside it. Columns are named rather than positional
    # because the access schema gains columns across macOS releases.
    for client in /usr/bin/osascript /bin/bash /bin/zsh; do
        sudo sqlite3 "$USER_TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier, flags, last_modified) VALUES ('kTCCServiceAppleEvents', '$client', 1, 2, 0, 1, 0, 'com.apple.finder', 0, strftime('%s','now'));"
    done
    sudo chown -R "$(id -un):staff" "$(dirname "$USER_TCC_DB")"

    # tccd holds the database open, so restart it to pick the rows up.
    killall tccd 2>/dev/null || true

    sqlite3 "$USER_TCC_DB" "SELECT 1 FROM access WHERE service='kTCCServiceAppleEvents' AND client='/usr/bin/osascript' AND indirect_object_identifier='com.apple.finder' AND auth_value=2;" | grep -q 1 || {
        echo "sanity check: AppleEvents approval for Finder did not persist to the per-user TCC.db, so create-dmg would spend 10 minutes timing out instead" >&2
        exit 1
    }
fi

print_status "Creating DMG..."
# Retries cover the "Can't get disk (-1728)" race create-dmg warns about; the
# Finder authorization it also needs is seeded above.
max_attempts=5
attempt=1
until create-dmg --background $MISE_PROJECT_ROOT/assets/dmg-background.png --hide-extension "Tuist.app" --icon "Tuist.app" 139 161 --icon-size 95 --window-size 605 363 --app-drop-link 467 161 --volname "Tuist App" "$BUILD_DMG_PATH" "$BUILD_DIRECTORY_BINARY"; do
    if [ $attempt -ge $max_attempts ]; then
        echo "create-dmg failed after $attempt attempts" >&2
        exit 1
    fi
    echo "create-dmg attempt $attempt failed; retrying..." >&2
    rm -f "$BUILD_DMG_PATH"
    attempt=$((attempt + 1))
    sleep 5
done

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
