#!/bin/bash
# Render the shipping Icon Composer source for Tuist Code.
set -euo pipefail
cd "$(dirname "$0")/.."
source_icon="$PWD/../app/Resources/TuistApp/AppIcon.icon"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/ios" "$scratch/macos" ios/Resources macos/Resources android/res/drawable-nodpi
xcrun actool "$source_icon" --compile "$scratch/ios" --platform iphonesimulator \
  --minimum-deployment-target 17.0 --app-icon AppIcon \
  --output-partial-info-plist "$scratch/ios.plist"
xcrun actool "$source_icon" --compile "$scratch/macos" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$scratch/macos.plist"
# Explicit resources keep actool's loose icon files in Once's cached bundle outputs.
cp "$scratch/ios/"*.png ios/Resources/
cp "$scratch/macos/AppIcon.icns" macos/Resources/
developer=$(xcode-select -p)
ictool="$developer/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$ictool" "$source_icon" --export-image --output-file "$scratch/icon.png" \
  --platform iOS --rendition Default --width 192 --height 192 --scale 1
cp "$scratch/icon.png" android/res/drawable-nodpi/app_icon.png
cp "$scratch/icon.png" gpui/resources/rounded-icon.png
# Desktop packaging and the unbundled GPUI Dock use the macOS rendition.
"$ictool" "$source_icon" --export-image --output-file "$scratch/desktop.png" \
  --platform macOS --rendition Default --width 256 --height 256 --scale 1
cp "$scratch/desktop.png" gpui/resources/icon.png
