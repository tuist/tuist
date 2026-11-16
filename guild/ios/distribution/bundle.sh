#!/usr/bin/env bash
# Signs a copy of the TuistGuildIOSDevice build for registered devices and packages
# delivery/ios-device/TuistGuild.ipa. Follows atlas-native/ios/distribution/bundle.sh:
# the shared Apple Distribution certificate plus the Tuist Code Ad Hoc profile, both
# read from 1Password into a disposable keychain. Never mutates Once's outputs.
set -euo pipefail
umask 077

cd "$(dirname "$0")/../.."
# shellcheck source-path=SCRIPTDIR/../..
source ios/distribution/keychain.sh
app_source="$PWD/.once/out/TuistGuildIOSDevice/TuistGuild.app"
team=U6LC622NKF
application_id="$team.dev.tuist.code"
profile_ref="op://tuist/Tuist Code Ad Hoc/Tuist_Code_Ad_Hoc.mobileprovision"
plist=/usr/libexec/PlistBuddy
fail() { echo "$*" >&2; exit 1; }
test -d "$app_source" || fail "Run mise run build:ios-device first"

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
[[ $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s) -gt $(date +%s) ]] || fail "The Tuist Guild provisioning profile has expired"
identity=$(plutil -extract DeveloperCertificates.0 raw "$tmp/profile.plist" | base64 -D | shasum -a 1 | awk '{print toupper($1)}')

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
ditto "$app_source" "$tmp/Payload/TuistGuild.app"
app="$tmp/Payload/TuistGuild.app"
[[ "$("$plist" -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = dev.tuist.code ]] || fail "Expected the Tuist Guild app"
xcrun vtool -show-build "$app/TuistGuild" | grep -Eq 'platform IOS$' || fail "Expected an iOS device build"
cp "$tmp/profile.mobileprovision" "$app/embedded.mobileprovision"
# Keep preview versions increasing without putting delivery metadata in cached outputs.
"$plist" -c "Set :CFBundleVersion $(date +%s)" "$app/Info.plist"
codesign --force --sign "$identity" --keychain "$keychain" --entitlements "$tmp/entitlements.plist" --timestamp=none "$app"
codesign --verify --strict --deep "$app"

mkdir -p delivery/ios-device
rm -f delivery/ios-device/TuistGuild.ipa
ditto -c -k --keepParent "$tmp/Payload" delivery/ios-device/TuistGuild.ipa
echo "Created delivery/ios-device/TuistGuild.ipa for the devices registered in Tuist Code Ad Hoc"
