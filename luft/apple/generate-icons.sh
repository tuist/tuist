#!/bin/bash
# Render Luft's icon: the shipping Icon Composer layers on a dark editor background.
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
source_icon="$scratch/AppIcon.icon"
cp -R ../app/Resources/TuistApp/AppIcon.icon "$source_icon"
plutil -replace fill -json '{
  "linear-gradient": ["display-p3:0.25000,0.24000,0.36000,1.00000", "srgb:0.05000,0.05000,0.09000,1.00000"],
  "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 0.7}}
}' "$source_icon/icon.json"
mkdir -p "$scratch/ios" "$scratch/macos" ios/Resources macos/Resources android/res/drawable-nodpi
xcrun actool "$source_icon" --compile "$scratch/ios" --platform iphonesimulator \
  --minimum-deployment-target 17.0 --app-icon AppIcon \
  --output-partial-info-plist "$scratch/ios.plist"
xcrun actool "$source_icon" --compile "$scratch/macos" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$scratch/macos.plist"
# Explicit resources keep actool's loose icon files in Struo's cached bundle outputs.
cp "$scratch/ios/"*.png ios/Resources/
cp "$scratch/macos/AppIcon.icns" macos/Resources/
developer=$(xcode-select -p)
ictool="$developer/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$ictool" "$source_icon" --export-image --output-file "$scratch/icon.png" \
  --platform iOS --rendition Default --width 192 --height 192 --scale 1
cp "$scratch/icon.png" android/res/drawable-nodpi/app_icon.png
cp "$scratch/icon.png" gpui/resources/rounded-icon.png
# Desktop packaging and the unbundled GPUI Dock use the macOS rendition. ictool
# fills the canvas, so pad it to Apple's icon grid (an 824pt body on a 1024pt
# canvas) or the Dock shows it larger than bundled apps.
"$ictool" "$source_icon" --export-image --output-file "$scratch/desktop.png" \
  --platform macOS --rendition Default --width 206 --height 206 --scale 1
sips --padToHeightWidth 256 256 "$scratch/desktop.png" >/dev/null
cp "$scratch/desktop.png" gpui/resources/icon.png
