#!/usr/bin/env bash
set -euo pipefail

[[ $# = 1 && -d "$1/Versions/B" ]] || { echo 'Usage: test-framework-boundary.sh <Sparkle.framework>' >&2; exit 2; }
source_framework=$(cd "$1" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
manifest() (
    cd "$source_framework"
    find -s . -type f -exec shasum -a 256 {} +
    find -s . -type l -print -exec readlink {} \;
)
manifest > "$tmp/before"
framework="$tmp/working/Sparkle.framework"
ditto "$source_framework" "$framework"
rm -rf "$framework/_CodeSignature"
mkdir "$framework/_CodeSignature"
cp "$framework/Versions/B/_CodeSignature/CodeResources" "$framework/_CodeSignature/CodeResources"
if codesign --verify --deep --strict "$framework" > "$tmp/invalid.log" 2>&1; then
    echo 'Unexpected acceptance of an invalid framework root signature directory' >&2; exit 1
fi

rm -rf "$framework/_CodeSignature"
ln -s Versions/Current/_CodeSignature "$framework/_CodeSignature"
for code in Autoupdate Updater.app XPCServices/Downloader.xpc XPCServices/Installer.xpc; do
    codesign --force --sign - --timestamp=none --options 0 "$framework/Versions/B/$code"
done
codesign --force --sign - --timestamp=none --options 0 "$framework"
codesign --verify --deep --strict "$framework"
copied="$tmp/copied/Sparkle.framework"
ditto "$framework" "$copied"
mkdir -p "$(dirname "$copied/_CodeSignature/CodeResources")"
[[ -L "$copied/_CodeSignature" && $(readlink "$copied/_CodeSignature") = Versions/Current/_CodeSignature ]]
for code in Sparkle Autoupdate Updater.app/Contents/MacOS/Updater XPCServices/Downloader.xpc/Contents/MacOS/Downloader XPCServices/Installer.xpc/Contents/MacOS/Installer; do
    [[ -x "$copied/Versions/B/$code" ]]
done
codesign --verify --deep --strict "$copied"
manifest > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
echo 'Sparkle framework boundary passed (invalid root rejected, copied symlink and helpers verified, cached source unchanged)'
