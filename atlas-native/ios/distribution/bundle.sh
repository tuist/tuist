#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/../.."
app_source="$PWD/.once/out/AtlasIOSDevice/Atlas.app"
test -d "$app_source" || { echo "Run mise run build:ios-device first" >&2; exit 1; }

# Never modify Once's cached bundle or import private keys into the login keychain.
tmp=$(mktemp -d)
keychain="$tmp/signing.keychain-db"
cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$tmp"
}
trap cleanup EXIT

op read "op://tuist/Distribution Certificate/distribution.p12" --out-file "$tmp/certificate.p12"
op read "op://tuist/Atlas App Ad Hoc/Atlas_App_Ad_Hoc.mobileprovision" --out-file "$tmp/profile.mobileprovision"
certificate_password=$(op read "op://tuist/Distribution Certificate/password")
keychain_password=$(uuidgen)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$tmp/certificate.p12" -k "$keychain" -P "$certificate_password" -T /usr/bin/codesign >/dev/null
unset certificate_password
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security find-identity -v -p codesigning "$keychain" > "$tmp/identities.txt"
security cms -D -i "$tmp/profile.mobileprovision" > "$tmp/profile.plist"

mkdir -p "$tmp/Payload"
ditto "$app_source" "$tmp/Payload/Atlas.app"
app="$tmp/Payload/Atlas.app"
identity=$(python3 ios/distribution/profile.py "$tmp/profile.plist" "$app/Info.plist" "$tmp/identities.txt" "$tmp/entitlements.plist")
xcrun vtool -show-build "$app/Atlas" | grep -Eq 'platform IOS$'
cp "$tmp/profile.mobileprovision" "$app/embedded.mobileprovision"
# Keep nightly build versions monotonic without putting CI identity in cached outputs.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%s)" "$app/Info.plist"

mkdir -p "$app/Frameworks"
xcrun swift-stdlib-tool --copy --scan-executable "$app/Atlas" --platform iphoneos --destination "$app/Frameworks"
while IFS= read -r -d '' library; do
    codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$library"
done < <(find "$app/Frameworks" -name '*.dylib' -print0)
codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none \
    --generate-entitlement-der --entitlements "$tmp/entitlements.plist" "$app"
codesign --verify --deep --strict "$app"
mkdir -p delivery/ios-device
rm -f delivery/ios-device/Atlas.ipa
ditto -c -k --keepParent "$tmp/Payload" delivery/ios-device/Atlas.ipa
echo "Created delivery/ios-device/Atlas.ipa for the devices registered in Atlas App Ad Hoc"
