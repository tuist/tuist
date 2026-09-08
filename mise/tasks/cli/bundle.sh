#!/bin/bash
#MISE description="Bundles the CLI"

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
print_status() {
    echo -e "${GREEN}▶ $1${NC}"
}
XCODE_WORKSPACE_PATH=$MISE_PROJECT_ROOT/Tuist.xcworkspace
source $MISE_PROJECT_ROOT/mise/utilities/setup.sh
BUILD_DIRECTORY=$MISE_PROJECT_ROOT/build
TMP_DIR=/private$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT # Ensures it gets deleted
TUIST_DIR=$MISE_PROJECT_ROOT
# Every 1Password read happens here, before a keychain is created or anything
# is built, so a credentials problem fails in about a second with the full list
# of what is unreadable. `set -e` aborts on the first failing read, which used
# to surface as a bare `op` 401 forty lines in and read like a build failure.
CERTIFICATE_P12_PATH=$TMP_DIR/certificate.p12
OP_UNREADABLE=""
OP_READABLE=""
op_record() {
    if [ "$1" -eq 0 ]; then
        OP_READABLE="${OP_READABLE}${OP_READABLE:+
}  - $2"
    else
        OP_UNREADABLE="${OP_UNREADABLE}${OP_UNREADABLE:+
}  - $2"
    fi
}

# Redirected rather than captured in a subshell: the helpers have to record
# their outcome in this shell so one pass collects every failure.
op_read_field() {
    local rc=0
    op read "$1" >"$2" 2>/dev/null || rc=$?
    op_record "$rc" "$1"
}

op_read_file() {
    local rc=0
    op read "$1" --out-file "$2" >/dev/null 2>&1 || rc=$?
    op_record "$rc" "$1"
}

print_status "Checking access to signing credentials in 1Password..."
op_read_field "op://tuist/App Specific Password/username" "$TMP_DIR/apple_id"
op_read_field "op://tuist/App Specific Password/password" "$TMP_DIR/apple_password"
op_read_field "op://tuist/Developer ID Application Certificate/password" "$TMP_DIR/certificate_password"
op_read_file "op://tuist/Developer ID Application Certificate/certificate.p12" "$CERTIFICATE_P12_PATH"

if [ -n "$OP_UNREADABLE" ]; then
    {
        echo -e "${RED}[ERROR] Could not read the code-signing credentials from 1Password.${NC}"
        echo "This is a credentials failure, not a build failure. Nothing was built."
        echo
        echo "Unreadable:"
        echo "$OP_UNREADABLE"
        if [ -n "$OP_READABLE" ]; then
            echo "Readable:"
            echo "$OP_READABLE"
        fi
        echo
        if [ "${CI:-}" = "true" ]; then
            echo "CI authenticates with the OP_SERVICE_ACCOUNT_TOKEN secret. If some of"
            echo "the references above were readable and others were not, the token itself"
            echo "is valid and unexpired, so look at the refused items rather than rotating"
            echo "it. That pattern has two known causes: a transient 1Password-side error"
            echo "(re-run the job once before escalating), or the service account losing"
            echo "access to those items under 1Password > Developer > Service Accounts."
        else
            echo "Run 'op signin' and make sure your account can read the references above."
        fi
    } >&2
    exit 1
fi

APPLE_ID=$(cat "$TMP_DIR/apple_id")
APPLE_PASSWORD=$(cat "$TMP_DIR/apple_password")
CERTIFICATE_PASSWORD=$(cat "$TMP_DIR/certificate_password")
TEAM_ID='U6LC622NKF'
ASC_PROVIDER=PedroPieraBuendia211042238 # Obtained with xcrun altool -list-providers
CERTIFICATE_NAME="Developer ID Application: Tuist GmbH (U6LC622NKF)"
# Until Xcode 27's prefix mapping lands, a compilation-cache key embeds the
# DerivedData path, so a per-run temporary path gives every task a key no other
# run can match and the build misses the cache entirely. Keep this stable and
# repo-relative; $TMP_DIR stays for the keychain and certificate material.
DERIVED_DATA_PATH=$BUILD_DIRECTORY/derived-data
export TUIST_EE=1
KEYCHAIN_PATH=$TMP_DIR/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)

# Codesign
print_status "Setting up Keychain for signing..."
if [ "${CI:-}" = "true" ]; then
    print_status "Creating a new temporary keychain..."
    security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
    security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
    security default-keychain -s $KEYCHAIN_PATH
    security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
fi

print_status "Importing certificate to keychain..."
security import $CERTIFICATE_P12_PATH -P "$CERTIFICATE_PASSWORD" -A

echo "$(format_section "Building release into $BUILD_DIRECTORY")"

rm -rf $MISE_PROJECT_ROOT/Tuist.xcodeproj
rm -rf $MISE_PROJECT_ROOT/Tuist.xcworkspace
rm -rf $BUILD_DIRECTORY
mkdir -p $BUILD_DIRECTORY

build_project_desscription() {
    tuist generate --no-open --no-binary-cache --path $TUIST_DIR

    # `tuist xcodebuild` carries a single action, so the clean stays a separate
    # raw invocation; the build is routed through tuist for build insights + caching.
    xcrun xcodebuild -workspace $TUIST_DIR/Tuist.xcworkspace -scheme ProjectDescription -derivedDataPath $DERIVED_DATA_PATH -configuration Release clean
    tuist xcodebuild build -workspace $TUIST_DIR/Tuist.xcworkspace -scheme ProjectDescription -derivedDataPath $DERIVED_DATA_PATH -configuration Release -destination platform=macOS BUILD_LIBRARY_FOR_DISTRIBUTION=YES ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO

    rsync -a $DERIVED_DATA_PATH/Build/Products/Release/ProjectDescription.framework $BUILD_DIRECTORY/
    rsync -a $DERIVED_DATA_PATH/Build/Products/Release/ProjectDescription.framework.dSYM $BUILD_DIRECTORY/
}

build_cli() {
    # arm64
    BINARY_PATH=$DERIVED_DATA_PATH/Build/Products/Release/tuist
    tuist xcodebuild build \
        -configuration Release \
        -workspace $XCODE_WORKSPACE_PATH \
        -scheme tuist \
        -derivedDataPath $DERIVED_DATA_PATH \
        -destination generic/platform=macOS \
        ONLY_ACTIVE_ARCH=NO \
        SKIP_INSTALL=NO \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="\"\"" \
        CODE_SIGN_ENTITLEMENTS="\"\"" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO

    mv $BINARY_PATH $BUILD_DIRECTORY/tuist
}

bundle_swift_runtime_libraries() {
    VENDOR_DIRECTORY=$BUILD_DIRECTORY/vendor
    mkdir -p "$VENDOR_DIRECTORY"

    xcrun swift-stdlib-tool --copy \
        --scan-executable "$BUILD_DIRECTORY/tuist" \
        --scan-executable "$BUILD_DIRECTORY/ProjectDescription.framework/ProjectDescription" \
        --platform macosx \
        --destination "$VENDOR_DIRECTORY"

    if find "$VENDOR_DIRECTORY" -type f -name "*.dylib" -print -quit | grep -q .; then
        install_name_tool -add_rpath "@executable_path/vendor" "$BUILD_DIRECTORY/tuist"
        install_name_tool -add_rpath "@loader_path/../../../vendor" "$BUILD_DIRECTORY/ProjectDescription.framework/ProjectDescription"
    fi
}

strip_release_binaries() {
    strip -rSTx \
        "$BUILD_DIRECTORY/tuist" \
        "$BUILD_DIRECTORY/ProjectDescription.framework/ProjectDescription" \
        "$BUILD_DIRECTORY/libtuist_cas_plugin.dylib" \
        "$BUILD_DIRECTORY/tuist-cas-proxy"
}

# Builds the cas-plugin (Xcode compilation-cache CAS plugin) as a universal
# dylib, plus the per-machine proxy binary, both bundled next to `tuist`. The
# CLI points Xcode's compilation caching at the dylib via
# COMPILATION_CACHE_PLUGIN_PATH and launches the proxy via `tuist cache-proxy`;
# ResourceLocator resolves both relative to the executable. Both are
# self-contained (Rust deps statically linked), so no rpath wiring is needed.
build_cas_plugin() {
    CAS_TARGET_DIR=$TMP_DIR/cas-plugin-target
    (
        # Run rust from the crate dir so mise resolves the toolchain version
        # from cas-plugin/mise.toml (the single source of truth).
        cd "$TUIST_DIR/cas-plugin" || exit 1
        rustup target add aarch64-apple-darwin x86_64-apple-darwin
        cargo build --release --lib --bin tuist-cas-proxy --target aarch64-apple-darwin --target-dir "$CAS_TARGET_DIR"
        cargo build --release --lib --bin tuist-cas-proxy --target x86_64-apple-darwin --target-dir "$CAS_TARGET_DIR"
    )
    lipo -create \
        "$CAS_TARGET_DIR/aarch64-apple-darwin/release/libtuist_cas_plugin.dylib" \
        "$CAS_TARGET_DIR/x86_64-apple-darwin/release/libtuist_cas_plugin.dylib" \
        -output "$BUILD_DIRECTORY/libtuist_cas_plugin.dylib"
    # Replace the build-path install id with the bare name (the plugin is loaded
    # by absolute path, so the id is cosmetic but a build path is not shippable).
    install_name_tool -id "libtuist_cas_plugin.dylib" "$BUILD_DIRECTORY/libtuist_cas_plugin.dylib"
    lipo -create \
        "$CAS_TARGET_DIR/aarch64-apple-darwin/release/tuist-cas-proxy" \
        "$CAS_TARGET_DIR/x86_64-apple-darwin/release/tuist-cas-proxy" \
        -output "$BUILD_DIRECTORY/tuist-cas-proxy"
}

echo "$(format_section "Building")"

echo "$(format_subsection "Generating Xcode project")"
TUIST_FORCE_STATIC_LINKING=1 tuist generate --no-binary-cache --path $MISE_PROJECT_ROOT --no-open

echo "$(format_subsection "Building tuist executable")"
build_cli

echo "$(format_subsection "Building ProjectDescription framework")"
build_project_desscription

echo "$(format_subsection "Building cas-plugin dylib")"
build_cas_plugin

echo "$(format_subsection "Bundling Swift runtime libraries")"
bundle_swift_runtime_libraries

echo "$(format_subsection "Stripping release binaries")"
strip_release_binaries

echo "$(format_section "Copying assets")"

echo "$(format_subsection "Copying Tuist's templates")"
cp -r $TUIST_DIR/cli/Templates $BUILD_DIRECTORY/Templates

echo "$(format_section "Bundling")"

(
    cd $BUILD_DIRECTORY || exit 1

    echo "$(format_subsection "Signing")"
    if [ -d vendor ]; then
        find vendor -type f -name "*.dylib" -print0 | while IFS= read -r -d '' library; do
            /usr/bin/codesign --force --sign "$CERTIFICATE_NAME" --timestamp --options runtime --verbose "$library"
        done
    fi
    /usr/bin/codesign --force --sign "$CERTIFICATE_NAME" --timestamp --options runtime --verbose libtuist_cas_plugin.dylib
    /usr/bin/codesign --force --sign "$CERTIFICATE_NAME" --timestamp --options runtime --verbose tuist-cas-proxy
    /usr/bin/codesign --force --sign "$CERTIFICATE_NAME" --timestamp --options runtime --verbose tuist
    /usr/bin/codesign --force --sign "$CERTIFICATE_NAME" --timestamp --options runtime --verbose ProjectDescription.framework

    echo "$(format_subsection "Notarizing")"
    zip -q -r --symlinks "notarization-bundle.zip" tuist ProjectDescription.framework vendor libtuist_cas_plugin.dylib tuist-cas-proxy

    RAW_JSON=$(xcrun notarytool submit "notarization-bundle.zip" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APPLE_PASSWORD" \
        --output-format json)
    echo "$RAW_JSON"
    SUBMISSION_ID=$(echo "$RAW_JSON" | jq -r '.id')
    echo "Submission ID: $SUBMISSION_ID"

    while true; do
        STATUS=$(xcrun notarytool info "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APPLE_PASSWORD" \
            --output-format json | jq -r '.status')

        case $STATUS in
            "Accepted")
                echo -e "${GREEN}Notarization succeeded!${NC}"
                break
                ;;
            "In Progress")
                echo "Notarization in progress... waiting 30 seconds"
                sleep 30
                ;;
            "Invalid"|"Rejected")
                echo "Notarization failed with status: $STATUS"
                xcrun notarytool log "$SUBMISSION_ID" \
                    --apple-id "$APPLE_ID" \
                    --team-id "$TEAM_ID" \
                    --password "$APPLE_PASSWORD"
                exit 1
                ;;
            *)
                echo "Unknown status: $STATUS"
                exit 1
                ;;
        esac
    done
    rm "notarization-bundle.zip"

    echo "$(format_subsection "Bundling tuist.zip")"
    zip -q -r --symlinks tuist.zip tuist ProjectDescription.framework ProjectDescription.framework.dSYM Templates vendor libtuist_cas_plugin.dylib tuist-cas-proxy

    echo "$(format_subsection "Bundling ProjectDescription.xcframework.zip")"
    xcodebuild -create-xcframework -framework ProjectDescription.framework -output ProjectDescription.xcframework
    zip -q -r --symlinks ProjectDescription.xcframework.zip ProjectDescription.xcframework

    echo "$(format_subsection "Generating tuist.spec.json")"
    SPEC_TMP_DIR=$(mktemp -d)
    ./tuist --experimental-dump-help --path "$SPEC_TMP_DIR" > tuist.spec.json
    rm -rf "$SPEC_TMP_DIR"

    rm -rf tuist ProjectDescription.framework ProjectDescription.xcframework ProjectDescription.framework.dSYM Templates vendor libtuist_cas_plugin.dylib tuist-cas-proxy

    : > SHASUMS256.txt
    : > SHASUMS512.txt

    for file in *; do
        if [ -f "$file" ]; then
            if [[ "$file" == "SHASUMS256.txt" || "$file" == "SHASUMS512.txt" ]]; then
                continue
            fi
            echo "$(shasum -a 256 "$file" | awk '{print $1}') ./$file" >> SHASUMS256.txt
            echo "$(shasum -a 512 "$file" | awk '{print $1}') ./$file" >> SHASUMS512.txt
        fi
    done
)
