#!/usr/bin/env bash
set -euo pipefail

[[ $# = 1 || ( $# = 2 && $2 = --distribution ) ]] || { echo 'Usage: validate.sh <Atlas.app> [--distribution]' >&2; exit 2; }
app=$1
plist="$app/Contents/Info.plist"
buddy=/usr/libexec/PlistBuddy
fail() { echo "$*" >&2; exit 1; }
[[ -f "$plist" && -x "$app/Contents/MacOS/Atlas" ]] || fail 'Expected a macOS Contents bundle'
[[ "$("$buddy" -c 'Print :CFBundleIdentifier' "$plist")" = dev.tuist.atlas.macos ]] || fail 'Unexpected Atlas bundle identity'
[[ "$("$buddy" -c 'Print :CFBundleExecutable' "$plist")" = Atlas ]] || fail 'Unexpected executable'
[[ "$("$buddy" -c 'Print :CFBundleIconFile' "$plist")" = Atlas.icns ]] || fail 'Missing Atlas icon declaration'
icon="$app/Contents/Resources/Atlas.icns"
[[ -f "$icon" && ! -L "$icon" ]] || fail 'Missing bundled Atlas icon'
[[ "$(/usr/bin/sips -g format "$icon" | awk '$1 == "format:" { print $2 }')" = icns ]] || fail 'Atlas icon must be a valid ICNS image'
icon_check=$(mktemp -d)
trap 'rm -rf "$icon_check"' EXIT
/usr/bin/sips -s format png "$icon" --out "$icon_check/Atlas.png" >/dev/null || fail 'Atlas icon could not be decoded'
[[ "$("$buddy" -c 'Print :LSMinimumSystemVersion' "$plist")" = 14.0 ]] || fail 'Atlas requires macOS 14'
[[ "$("$buddy" -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$plist")" = dev.tuist.atlas ]] || fail 'Missing Atlas URL scheme'
[[ "$("$buddy" -c 'Print :SUPublicEDKey' "$plist")" = 'XUfguyGrLktmv6E4C/iqfw8p57HWKqx4mJ/hG4/lbMk=' ]] || fail 'Unexpected Sparkle public key'
[[ "$("$buddy" -c 'Print :SUFeedURL' "$plist")" = https://github.com/tuist/tuist/releases/download/atlas-appcast/atlas-appcast.xml ]] || fail 'Unexpected Atlas feed'
for key in NSSupportsLiveActivities LSRequiresIPhoneOS; do
    if "$buddy" -c "Print :$key" "$plist" >/dev/null 2>&1; then fail "iOS-only key $key in macOS app"; fi
done
if [[ ${2:-} = --distribution ]]; then
    [[ -f "$app/Contents/embedded.provisionprofile" && ! -L "$app/Contents/embedded.provisionprofile" ]] || fail 'Distribution requires an embedded Developer ID profile'
    [[ $(plutil -extract AtlasPushEnvironment raw -expect string -o - "$plist") = production ]] || fail 'Distribution must declare profile-derived production APNs'
else
    [[ ! -e "$app/Contents/embedded.provisionprofile" && ! -L "$app/Contents/embedded.provisionprofile" ]] || fail 'Local builds must not embed a push provisioning profile'
    if "$buddy" -c 'Print :AtlasPushEnvironment' "$plist" >/dev/null 2>&1; then fail 'Local builds must not claim configured notifications'; fi
fi
[[ ! -d "$app/Contents/PlugIns" ]] || fail 'macOS must not embed the iOS Live Activity'
framework="$app/Contents/Frameworks/Sparkle.framework"
for code in Sparkle Autoupdate Updater.app/Contents/MacOS/Updater XPCServices/Downloader.xpc/Contents/MacOS/Downloader XPCServices/Installer.xpc/Contents/MacOS/Installer; do
    [[ -x "$framework/Versions/B/$code" ]] || fail "Missing Sparkle code: $code"
done
[[ -L "$framework/Versions/Current" && -f "$framework/Resources/Info.plist" ]] || fail 'Sparkle framework symlinks/resources were lost'
metadata=$(xcrun vtool -show-build "$app/Contents/MacOS/Atlas")
[[ "$(awk '$1 == "platform" { print $2 }' <<< "$metadata")" = MACOS ]] || fail 'Expected a macOS Mach-O'
[[ "$(awk '$1 == "minos" { print $2 }' <<< "$metadata")" = 14.0 ]] || fail 'Mach-O minimum is not macOS 14'
[[ "$(awk '$1 == "sdk" { print $2 }' <<< "$metadata")" = "$(xcrun --sdk macosx --show-sdk-version)" ]] || fail 'Mach-O must use the selected Xcode SDK'
[[ $(xcrun lipo -archs "$app/Contents/MacOS/Atlas") = arm64 ]] || fail 'Expected the Apple silicon macOS executable'
otool -L "$app/Contents/MacOS/Atlas" | grep -F '@rpath/Sparkle.framework/' >/dev/null || fail 'Atlas does not link Sparkle'
otool -l "$app/Contents/MacOS/Atlas" | grep -F '@executable_path/../Frameworks' >/dev/null || fail 'Missing macOS framework runpath'
