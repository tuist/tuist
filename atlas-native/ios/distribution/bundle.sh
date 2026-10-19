#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/../.."
app_source="$PWD/.once/out/AtlasIOSDevice/Atlas.app"
plist=/usr/libexec/PlistBuddy
fail() { echo "$*" >&2; exit 1; }
test -d "$app_source" || fail "Run mise run build:ios-device first"

# Sign a copy, keeping credentials outside Once's cache and the login keychain.
tmp=$(mktemp -d)
keychain="$tmp/signing.keychain-db"
default_keychain=""
restore_default_keychain=false
cleanup() {
    if "$restore_default_keychain"; then
        if [[ -n "$default_keychain" ]]; then
            security default-keychain -d user -s "$default_keychain" >/dev/null 2>&1 || true
        else
            security default-keychain -d user -s >/dev/null 2>&1 || true
        fi
    fi
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

op read "op://tuist/Atlas App Ad Hoc/Atlas_App_Ad_Hoc.mobileprovision" --out-file "$tmp/profile.mobileprovision"
security cms -D -i "$tmp/profile.mobileprovision" > "$tmp/profile.plist"
application_id="U6LC622NKF.dev.tuist.atlas"
[[ "$("$plist" -c 'Print :Entitlements:application-identifier' "$tmp/profile.plist")" = "$application_id" ]] || fail "Expected the Atlas provisioning profile"
[[ "$("$plist" -c 'Print :Entitlements:com.apple.developer.team-identifier' "$tmp/profile.plist")" = U6LC622NKF ]] || fail "Expected the Tuist signing team"
[[ "$("$plist" -c 'Print :Entitlements:get-task-allow' "$tmp/profile.plist")" = false ]] || fail "Use an ad-hoc profile, not a development profile"
"$plist" -c 'Print :ProvisionedDevices:0' "$tmp/profile.plist" >/dev/null || fail "The profile must include registered devices"
expires=$(plutil -extract ExpirationDate raw "$tmp/profile.plist")
[[ $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s) -gt $(date +%s) ]] || fail "The Atlas provisioning profile has expired"

op read "op://tuist/Distribution Certificate/distribution.p12" --out-file "$tmp/certificate.p12"
certificate_password=$(op read "op://tuist/Distribution Certificate/password")
keychain_password=$(uuidgen)
if [[ "${CI:-}" = true ]]; then
    security default-keychain -d user > "$tmp/default-keychain.txt"
    read -r default_keychain < "$tmp/default-keychain.txt" || true
    default_keychain="${default_keychain//\"/}"
    restore_default_keychain=true
fi
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
if "$restore_default_keychain"; then
    security default-keychain -d user -s "$keychain"
fi
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$tmp/certificate.p12" -k "$keychain" -P "$certificate_password" -T /usr/bin/codesign >/dev/null
unset certificate_password
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
identity=$(plutil -extract DeveloperCertificates.0 raw "$tmp/profile.plist" | base64 -D | shasum -a 1 | awk '{print toupper($1)}')
security find-identity -v -p codesigning "$keychain" | grep -F "$identity" >/dev/null || fail "No valid signing identity matches the provisioning profile"

mkdir -p "$tmp/Payload"
ditto "$app_source" "$tmp/Payload/Atlas.app"
app="$tmp/Payload/Atlas.app"
[[ "$("$plist" -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = dev.tuist.atlas ]] || fail "Expected the production Atlas app"
xcrun vtool -show-build "$app/Atlas" | grep -Eq 'platform IOS$' || fail "Expected an iOS device build"
cp "$tmp/profile.mobileprovision" "$app/embedded.mobileprovision"
plutil -extract Entitlements xml1 -o "$tmp/entitlements.plist" "$tmp/profile.plist"
plutil -replace keychain-access-groups -json "[\"$application_id\"]" "$tmp/entitlements.plist"
# Keep nightly versions increasing without putting delivery metadata in cached outputs.
"$plist" -c "Set :CFBundleVersion $(date +%s)" "$app/Info.plist"

mkdir -p "$app/Frameworks"
xcrun swift-stdlib-tool --copy --scan-executable "$app/Atlas" --platform iphoneos --destination "$app/Frameworks"
while IFS= read -r -d '' library; do
    codesign --verbose=2 --force --sign "$identity" --keychain "$keychain" --timestamp=none "$library"
done < <(find "$app/Frameworks" -name '*.dylib' -print0)
codesign --verbose=2 --force --sign "$identity" --keychain "$keychain" --timestamp=none \
    --generate-entitlement-der --entitlements "$tmp/entitlements.plist" "$app"
codesign --verify --deep --strict "$app"
mkdir -p delivery/ios-device
rm -f delivery/ios-device/Atlas.ipa
ditto -c -k --keepParent "$tmp/Payload" delivery/ios-device/Atlas.ipa
echo "Created delivery/ios-device/Atlas.ipa for the devices registered in Atlas App Ad Hoc"
