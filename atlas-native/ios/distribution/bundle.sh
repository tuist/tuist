#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/../.."
source ios/distribution/keychain.sh
source ios/distribution/associated-domains.sh
source ios/distribution/push.sh
source ios/distribution/live-activity.sh
source ios/distribution/share.sh
app_source="$PWD/.once/out/AtlasIOSDevice/Atlas.app"
plist=/usr/libexec/PlistBuddy
fail() { echo "$*" >&2; exit 1; }
test -d "$app_source" || fail "Run mise run build:ios-device first"
validate_live_activity_bundle "$app_source"
validate_share_bundle "$app_source"

# Sign a copy, keeping credentials outside Once's cache and the login keychain.
tmp=$(mktemp -d)
keychain="$tmp/signing.keychain-db"
cleanup() {
    delete_signing_keychain "$keychain" || true
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

plutil -extract Entitlements xml1 -o "$tmp/entitlements.plist" "$tmp/profile.plist"
plutil -replace keychain-access-groups -json "[\"$application_id\"]" "$tmp/entitlements.plist"
configure_associated_domains "$tmp/profile.plist" "$tmp/entitlements.plist"
configure_push_notifications "$tmp/profile.plist" "$tmp/entitlements.plist"
configure_share_group "$tmp/profile.plist" "$tmp/entitlements.plist"

identity=$(plutil -extract DeveloperCertificates.0 raw "$tmp/profile.plist" | base64 -D | shasum -a 1 | awk '{print toupper($1)}')
op read "op://tuist/Atlas Live Activity Ad Hoc/Atlas_Live_Activity_Ad_Hoc.mobileprovision" --out-file "$tmp/activity.mobileprovision"
security cms -D -i "$tmp/activity.mobileprovision" > "$tmp/activity-profile.plist"
validate_live_activity_profile "$tmp/activity-profile.plist" "$tmp/profile.plist" "$identity"
op read "op://tuist/Atlas Share Ad Hoc/Atlas_Share_Ad_Hoc.mobileprovision" --out-file "$tmp/share.mobileprovision"
security cms -D -i "$tmp/share.mobileprovision" > "$tmp/share-profile.plist"
validate_live_activity_profile "$tmp/share-profile.plist" "$tmp/profile.plist" "$identity" dev.tuist.atlas.share
# Validate capability authorization before retrieving any private signing material.
plutil -extract Entitlements xml1 -o "$tmp/share-entitlements.plist" "$tmp/share-profile.plist"
configure_share_group "$tmp/share-profile.plist" "$tmp/share-entitlements.plist"

op read "op://tuist/Distribution Certificate/distribution.p12" --out-file "$tmp/certificate.p12"
certificate_password=$(op read "op://tuist/Distribution Certificate/password")
keychain_password=$(uuidgen)
create_signing_keychain "$keychain" "$keychain_password"
security import "$tmp/certificate.p12" -k "$keychain" -P "$certificate_password" -T /usr/bin/codesign >/dev/null
unset certificate_password
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security find-identity -v -p codesigning "$keychain" | grep -F "$identity" >/dev/null || fail "No valid signing identity matches the provisioning profile"

mkdir -p "$tmp/Payload"
ditto "$app_source" "$tmp/Payload/Atlas.app"
app="$tmp/Payload/Atlas.app"
[[ "$("$plist" -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = dev.tuist.atlas ]] || fail "Expected the production Atlas app"
xcrun vtool -show-build "$app/Atlas" | grep -Eq 'platform IOS$' || fail "Expected an iOS device build"
cp "$tmp/profile.mobileprovision" "$app/embedded.mobileprovision"
"$plist" -c 'Set :AtlasPushEnvironment production' "$app/Info.plist"
# Keep nightly versions increasing without putting delivery metadata in cached outputs.
"$plist" -c "Set :CFBundleVersion $(date +%s)" "$app/Info.plist"

prepare_live_activity_distribution "$app" "$tmp/activity.mobileprovision" "$tmp/activity-entitlements.plist"
prepare_live_activity_distribution "$app" "$tmp/share.mobileprovision" "$tmp/share-entitlements.plist" AtlasShare
configure_share_group "$tmp/share-profile.plist" "$tmp/share-entitlements.plist"
sign_live_activity_distribution "$app" "$identity" "$keychain" "$tmp/entitlements.plist" "$tmp/activity-entitlements.plist" "$tmp/share-entitlements.plist"
mkdir -p delivery/ios-device
rm -f delivery/ios-device/Atlas.ipa
ditto -c -k --keepParent "$tmp/Payload" delivery/ios-device/Atlas.ipa
echo "Created delivery/ios-device/Atlas.ipa for the devices registered in Atlas App Ad Hoc"
