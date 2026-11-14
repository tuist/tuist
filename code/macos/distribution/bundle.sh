#!/usr/bin/env bash
# Signs a copy of the TuistCodeMacOS build with Tuist's Developer ID certificate,
# notarizes and staples it, and leaves delivery/macos/TuistCode.app. A stable
# Developer ID signature lets macOS remember "Always Allow" for the Tuist app's
# Keychain session; ad-hoc signatures change on every build, so macOS would ask
# again each time. Follows atlas-native/macos/distribution/bundle.sh without push
# provisioning: Tuist Code needs no restricted entitlements. Never mutates Once's
# outputs.
# Vault credentials must never enter inherited shell tracing or verbose output.
set +x +v
set -euo pipefail
umask 077

cd "$(dirname "$0")/../.."
# shellcheck source-path=SCRIPTDIR/../..
source ios/distribution/keychain.sh
app_source="$PWD/.once/out/TuistCodeMacOS/TuistCode.app"
team=U6LC622NKF
plist=/usr/libexec/PlistBuddy
fail() { echo "$*" >&2; exit 1; }
test -d "$app_source" || fail "Run mise run build:macos first"

tmp=$(mktemp -d)
keychain="$tmp/signing.keychain-db"
cleanup() {
    delete_signing_keychain "$keychain" > "$tmp/keychain.log" 2>&1 || echo 'Could not clean up the temporary signing keychain' >&2
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

app="$tmp/TuistCode.app"
ditto "$app_source" "$app"
[[ "$("$plist" -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = dev.tuist.code ]] || fail "Expected the Tuist Code app"
xcrun vtool -show-build "$app/Contents/MacOS/TuistCode" | grep -Eq 'platform MACOS$' || fail "Expected a macOS build"
# Keep preview versions increasing without putting delivery metadata in cached outputs.
"$plist" -c "Set :CFBundleVersion $(date +%s)" "$app/Contents/Info.plist"

# Provider diagnostics may echo credentials; keep them in this private directory.
op read 'op://tuist/Developer ID Application Certificate/certificate.p12' --out-file "$tmp/certificate.p12" > "$tmp/vault.log" 2>&1 || fail 'Could not read the Developer ID certificate'
certificate_password=$(op read 'op://tuist/Developer ID Application Certificate/password' 2> "$tmp/vault.log") || fail 'Could not read the Developer ID certificate password'
keychain_password=$(uuidgen)
create_signing_keychain "$keychain" "$keychain_password" > "$tmp/keychain.log" 2>&1 || fail 'Could not create the temporary signing keychain'
security import "$tmp/certificate.p12" -k "$keychain" -P "$certificate_password" -T /usr/bin/codesign > "$tmp/keychain.log" 2>&1 || fail 'Could not import the Developer ID certificate'
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" > "$tmp/keychain.log" 2>&1 || fail 'Could not authorize the signing key'
unset certificate_password keychain_password
identity=$(security find-identity -v -p codesigning "$keychain" \
    | awk -v team="($team)\"" 'index($0, "\"Developer ID Application:") && index($0, team) { print $2; exit }')
[[ $identity =~ ^[A-F0-9]{40}$ ]] || fail 'No Developer ID Application identity for the Tuist team'

# Hardened runtime with no entitlements: no sandbox, so the app reaches the Tuist
# app's login-keychain items and ~/.local/state/tuist like the Tuist app does.
codesign --force --sign "$identity" --keychain "$keychain" --options runtime --timestamp "$app"
codesign --verify --strict --deep "$app"
[[ "$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "$team" ]] || fail 'Expected the Tuist team signature'

ditto -c -k --sequesterRsrc --keepParent "$app" "$tmp/notarization.zip"
apple_id=$(op read 'op://tuist/App Specific Password/username' 2> "$tmp/vault.log") || fail 'Could not read the Apple notarization account'
notarization_password=$(op read 'op://tuist/App Specific Password/password' 2> "$tmp/vault.log") || fail 'Could not read the Apple notarization password'
xcrun notarytool submit "$tmp/notarization.zip" --wait --timeout 20m \
    --apple-id "$apple_id" --team-id "$team" --password "$notarization_password" \
    --output-format json > "$tmp/notarization.json" 2> "$tmp/notarization.log" || fail 'Apple notarization submission failed (private diagnostics withheld)'
unset apple_id notarization_password
[[ "$(plutil -extract status raw -o - "$tmp/notarization.json" 2>/dev/null)" = Accepted ]] || fail 'Notarization was not accepted'
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

mkdir -p delivery/macos
rm -rf delivery/macos/TuistCode.app
ditto "$app" delivery/macos/TuistCode.app
echo "Created delivery/macos/TuistCode.app, signed with Tuist's Developer ID and notarized"
