#!/usr/bin/env bash
# Signs a copy of the LuftIOSDevice build for registered devices and packages
# delivery/ios-device/Luft.ipa. Follows atlas-native/ios/distribution/bundle.sh:
# the shared Apple Distribution certificate plus the Tuist Code Ad Hoc profile for the
# app and the Tuist Code Live Activity Ad Hoc profile for its extension, all read from
# 1Password into a disposable keychain. Never mutates Struo's outputs.
set -euo pipefail
umask 077

cd "$(dirname "$0")/../.."
# shellcheck source-path=SCRIPTDIR/../..
source ios/distribution/keychain.sh
# shellcheck source-path=SCRIPTDIR/../..
source ios/distribution/live-activity.sh
app_source="$PWD/.struo/out/LuftIOSDevice/Luft.app"
team=U6LC622NKF
application_id="$team.dev.tuist.code"
profile_ref="op://tuist/Tuist Code Ad Hoc/Tuist_Code_Ad_Hoc.mobileprovision"
activity_profile_ref="op://tuist/Tuist Code Live Activity Ad Hoc/Tuist_Code_Live_Activity_Ad_Hoc.mobileprovision"
plist=/usr/libexec/PlistBuddy
fail() { echo "$*" >&2; exit 1; }
test -d "$app_source" || fail "Run mise run build:ios-device first"
validate_live_activity_bundle "$app_source" || fail "Expected the device LuftLiveActivity.appex embedded in the app"

tmp=$(mktemp -d)
keychain="$tmp/signing.keychain-db"
cleanup() {
    delete_signing_keychain "$keychain" || true
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Validate the profile before reading any private signing material.
op read "$profile_ref" --out-file "$tmp/profile.mobileprovision" >/dev/null
security cms -D -i "$tmp/profile.mobileprovision" > "$tmp/profile.plist"
[[ "$("$plist" -c 'Print :Entitlements:application-identifier' "$tmp/profile.plist")" = "$application_id" ]] || fail "Expected a provisioning profile for $application_id"
[[ "$("$plist" -c 'Print :Entitlements:com.apple.developer.team-identifier' "$tmp/profile.plist")" = "$team" ]] || fail "Expected the Tuist signing team"
[[ "$("$plist" -c 'Print :Entitlements:get-task-allow' "$tmp/profile.plist")" = false ]] || fail "Use an ad-hoc profile, not a development profile"
"$plist" -c 'Print :ProvisionedDevices:0' "$tmp/profile.plist" >/dev/null 2>&1 || fail "The profile must include registered devices"
expires=$(plutil -extract ExpirationDate raw "$tmp/profile.plist")
[[ $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s) -gt $(date +%s) ]] || fail "The Luft provisioning profile has expired"
identity=$(plutil -extract DeveloperCertificates.0 raw "$tmp/profile.plist" | base64 -D | shasum -a 1 | awk '{print toupper($1)}')
op read "$activity_profile_ref" --out-file "$tmp/activity.mobileprovision" >/dev/null
security cms -D -i "$tmp/activity.mobileprovision" > "$tmp/activity-profile.plist"
validate_live_activity_profile "$tmp/activity-profile.plist" "$tmp/profile.plist" "$identity" || fail "The Tuist Code Live Activity Ad Hoc profile can't sign this build"

# The vault is private to this app: keep Keychain access to its own group only.
plutil -extract Entitlements xml1 -o "$tmp/entitlements.plist" "$tmp/profile.plist"
plutil -replace keychain-access-groups -json "[\"$application_id\"]" "$tmp/entitlements.plist"

op read "op://tuist/Distribution Certificate/distribution.p12" --out-file "$tmp/certificate.p12" >/dev/null
certificate_password=$(op read "op://tuist/Distribution Certificate/password")
keychain_password=$(uuidgen)
create_signing_keychain "$keychain" "$keychain_password" || fail "Could not create the temporary signing keychain"
security import "$tmp/certificate.p12" -k "$keychain" -P "$certificate_password" -T /usr/bin/codesign >/dev/null
unset certificate_password
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security find-identity -v -p codesigning "$keychain" | grep -F "$identity" >/dev/null || fail "No valid signing identity matches the provisioning profile"

mkdir -p "$tmp/Payload"
ditto "$app_source" "$tmp/Payload/Luft.app"
app="$tmp/Payload/Luft.app"
[[ "$("$plist" -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = dev.tuist.code ]] || fail "Expected the Luft app"
xcrun vtool -show-build "$app/Luft" | grep -Eq 'platform IOS$' || fail "Expected an iOS device build"
cp "$tmp/profile.mobileprovision" "$app/embedded.mobileprovision"
# The profile carries aps-environment once the App ID has Push Notifications and the
# profile was regenerated; tell the app which APNs environment its tokens belong to.
case "$("$plist" -c 'Print :Entitlements:aps-environment' "$tmp/profile.plist" 2>/dev/null || true)" in
    production) "$plist" -c 'Set :LuftPushEnvironment production' "$app/Info.plist" ;;
    development) "$plist" -c 'Set :LuftPushEnvironment sandbox' "$app/Info.plist" ;;
    *) echo "The Tuist Code Ad Hoc profile has no push entitlement; this build won't receive notifications" >&2 ;;
esac
# Keep preview versions increasing without putting delivery metadata in cached outputs.
"$plist" -c "Set :CFBundleVersion $(date +%s)" "$app/Info.plist"
prepare_live_activity_distribution "$app" "$tmp/activity.mobileprovision" "$tmp/activity-entitlements.plist"
sign_live_activity_distribution "$app" "$identity" "$keychain" "$tmp/entitlements.plist" "$tmp/activity-entitlements.plist"

mkdir -p delivery/ios-device
rm -f delivery/ios-device/Luft.ipa
ditto -c -k --keepParent "$tmp/Payload" delivery/ios-device/Luft.ipa
echo "Created delivery/ios-device/Luft.ipa for the devices registered in Tuist Code Ad Hoc"
