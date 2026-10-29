#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $# = 3 && $3 =~ ^[1-9][0-9]{9,}$ ]] || { echo 'Usage: bundle.sh <Atlas.app> <new output directory> <epoch build number>' >&2; exit 2; }
scripts=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../ios/distribution/keychain.sh
source "$scripts/../../ios/distribution/keychain.sh"
source "$scripts/push.sh"
source_app=$1
output=$2
build=$3
[[ ! -e "$output" ]] || { echo 'Output directory must be new' >&2; exit 1; }
bash "$scripts/validate.sh" "$source_app"

tmp=$(mktemp -d)
keychain="$tmp/signing.keychain-db"
cleanup() {
    local status=$?
    delete_signing_keychain "$keychain" || status=1
    rm -rf "$tmp"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# All credentials stay in this temporary directory/keychain, outside Once.
op read 'op://tuist/Atlas macOS Developer ID/Atlas_macOS_Developer_ID.provisionprofile' --out-file "$tmp/profile.provisionprofile"
security cms -D -i "$tmp/profile.provisionprofile" > "$tmp/profile.plist"
# Reject missing/old/non-Push profiles before reading the private certificate.
validate_macos_push_profile "$tmp/profile.plist"
op read 'op://tuist/Developer ID Application Certificate/certificate.p12' --out-file "$tmp/certificate.p12"
certificate_password=$(op read 'op://tuist/Developer ID Application Certificate/password')
keychain_password=$(uuidgen)
create_signing_keychain "$keychain" "$keychain_password"
security import "$tmp/certificate.p12" -k "$keychain" -P "$certificate_password" -T /usr/bin/codesign >/dev/null
unset certificate_password
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
identity=$(macos_push_signing_identity "$tmp/profile.plist" "$keychain")

ditto "$source_app" "$tmp/Atlas.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$tmp/Atlas.app/Contents/Info.plist"
cp "$tmp/profile.provisionprofile" "$tmp/Atlas.app/Contents/embedded.provisionprofile"
environment=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.aps-environment' "$tmp/profile.plist")
/usr/libexec/PlistBuddy -c "Add :AtlasPushEnvironment string $environment" "$tmp/Atlas.app/Contents/Info.plist"
bash "$scripts/sign.sh" "$tmp/Atlas.app" "$identity" "$keychain"
ditto -c -k --sequesterRsrc --keepParent "$tmp/Atlas.app" "$tmp/notarization.zip"
xcrun notarytool submit "$tmp/notarization.zip" --wait --timeout 20m \
    --apple-id "$(op read 'op://tuist/App Specific Password/username')" \
    --team-id U6LC622NKF --password "$(op read 'op://tuist/App Specific Password/password')" \
    --output-format json > "$tmp/notarization.json"
[[ "$(plutil -extract status raw -o - "$tmp/notarization.json")" = Accepted ]] || { echo 'Notarization was not accepted' >&2; exit 1; }
xcrun stapler staple "$tmp/Atlas.app"
xcrun stapler validate "$tmp/Atlas.app"
codesign --verify --deep --strict "$tmp/Atlas.app"
spctl --assess --type execute --verbose=2 "$tmp/Atlas.app"

# The update signature and published checksums cover this final, stapled ZIP.
mkdir -p "$output"
ditto -c -k --sequesterRsrc --keepParent "$tmp/Atlas.app" "$output/Atlas-macos.zip"
(cd "$output" && shasum -a 256 Atlas-macos.zip > SHASUMS256.txt)
echo "Created $output/Atlas-macos.zip"
