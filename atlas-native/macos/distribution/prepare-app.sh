#!/usr/bin/env bash
set -euo pipefail

[[ $# = 2 ]] || { echo 'Usage: prepare-app.sh <Once source.app> <new runnable.app>' >&2; exit 2; }
source_app=$1
app=$2
scripts=$(cd "$(dirname "$0")" && pwd)
[[ -d "$source_app" && ! -e "$app" ]] || { echo 'Source must exist and destination must be new' >&2; exit 1; }
source_plist="$source_app/Info.plist"
if [[ -f "$source_app/Contents/Info.plist" ]]; then source_plist="$source_app/Contents/Info.plist"; fi
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$source_plist")
[[ "$executable" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Expected a simple bundle executable name' >&2; exit 1; }
mkdir -p "$(dirname "$app")"
ditto "$source_app" "$app"

# Once 0.68.2 emits flat Apple bundles. Never move its declared outputs.
if [[ ! -d "$app/Contents" ]]; then
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    mv "$app/$executable" "$app/Contents/MacOS/$executable"
    mv "$app/Info.plist" "$app/Contents/Info.plist"
    if [[ -d "$app/Frameworks" ]]; then mv "$app/Frameworks" "$app/Contents/Frameworks"; fi
    rm -rf "$app/_CodeSignature" "$app/embedded.provisionprofile"
    shopt -s dotglob nullglob
    for resource in "$app"/*; do
        [[ "$resource" = "$app/Contents" ]] || mv "$resource" "$app/Contents/Resources/"
    done
fi

# An ad-hoc copy cannot claim the restricted capability of a Developer ID build.
rm -f "$app/Contents/embedded.provisionprofile"
if /usr/libexec/PlistBuddy -c 'Print :AtlasPushEnvironment' "$app/Contents/Info.plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Delete :AtlasPushEnvironment' "$app/Contents/Info.plist"
fi

if [[ -d "$app/Contents/Frameworks/Sparkle.framework" ]]; then
    bash "$scripts/sign.sh" "$app" -
else
    # Isolated preview apps use their own plist/entry point and no updater.
    codesign --force --sign - --timestamp=none --entitlements "$scripts/entitlements.plist" "$app"
    codesign --verify --deep --strict "$app"
fi
