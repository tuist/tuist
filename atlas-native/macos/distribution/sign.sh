#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $# = 2 || $# = 3 ]] || { echo 'Usage: sign.sh <Atlas.app> <certificate SHA1 or -> [keychain]' >&2; exit 2; }
scripts=$(cd "$(dirname "$0")" && pwd)
source "$scripts/push.sh"
app=$1
identity=$2
framework="$app/Contents/Frameworks/Sparkle.framework"
entitlements="$scripts/entitlements.plist"
args=(--force --sign "$identity")
if [[ "$identity" = - ]]; then
    args+=(--timestamp=none --options 0)
else
    [[ $# = 3 && "$identity" =~ ^[A-F0-9]{40}$ ]] || { echo 'Developer ID signing requires an authorized certificate fingerprint and isolated keychain' >&2; exit 1; }
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    bash "$scripts/validate.sh" "$app" --distribution
    security cms -D -i "$app/Contents/embedded.provisionprofile" > "$work/profile.plist"
    entitlements="$work/entitlements.plist"
    write_macos_push_entitlements "$work/profile.plist" "$entitlements" "$scripts/entitlements.plist"
    [[ $(macos_push_signing_identity "$work/profile.plist" "$3") = "$identity" ]] || exit 1
    args+=(--timestamp --options runtime)
fi
if [[ $# = 3 ]]; then args+=(--keychain "$3"); fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")
if [[ "$identity" = - && "$bundle_id" = dev.tuist.atlas.macos ]]; then
    bash "$scripts/validate.sh" "$app"
elif [[ "$identity" = - ]]; then
    [[ "$bundle_id" = dev.tuist.atlas.macos.preview && "$executable" = AtlasMacOSPreview ]] || { echo 'Only the isolated preview may bypass production validation' >&2; exit 1; }
    [[ ! -e "$app/Contents/embedded.provisionprofile" ]] || exit 1
    ! /usr/libexec/PlistBuddy -c 'Print :AtlasPushEnvironment' "$app/Contents/Info.plist" >/dev/null 2>&1 || exit 1
fi
xcrun swift-stdlib-tool --copy --scan-executable "$app/Contents/MacOS/$executable" --platform macosx --destination "$app/Contents/Frameworks"
while IFS= read -r -d '' library; do
    codesign "${args[@]}" "$library"
done < <(find "$app/Contents/Frameworks" -type f -name '*.dylib' -print0)
# Sign nested executable/bundle roots before their containing framework and app.
codesign "${args[@]}" "$framework/Versions/B/Autoupdate"
codesign "${args[@]}" "$framework/Versions/B/Updater.app"
codesign "${args[@]}" "$framework/Versions/B/XPCServices/Downloader.xpc"
codesign "${args[@]}" "$framework/Versions/B/XPCServices/Installer.xpc"
codesign "${args[@]}" "$framework"
codesign "${args[@]}" --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"
if [[ "$identity" != - ]]; then verify_macos_push_signature "$app" "$identity" "$entitlements" "$work"; fi
