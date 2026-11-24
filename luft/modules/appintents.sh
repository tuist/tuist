#!/usr/bin/env bash
# Adds the App Intents metadata that Shortcuts, Siri and the Action button read.
# Struo does not run Xcode's metadata step, so this compiles the self-contained
# intents source for its constant values and runs Apple's processor on it.
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }
[[ $# = 3 ]] || fail "Pass the SDK (iphonesimulator or iphoneos), the intents Swift source and the assembled .app"
sdk=$1
source_file=$2
app=$3
module=Luft
case "$sdk" in
  iphonesimulator) triple=arm64-apple-ios17.0-simulator ;;
  iphoneos) triple=arm64-apple-ios17.0 ;;
  *) fail "Unexpected SDK $sdk" ;;
esac
[[ -f "$source_file" ]] || fail "Missing intents source $source_file"
[[ "$app" = *.app && -d "$app" && ! -L "$app" && -f "$app/Info.plist" ]] || fail "Expected an assembled .app"
source_file="$(cd "$(dirname "$source_file")" && pwd -P)/$(basename "$source_file")"
app=$(cd "$app" && pwd -P)

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Xcode's SWIFT_ENABLE_EMIT_CONST_VALUES gathers conformances to these protocols.
printf '%s' '["AppIntent","AppEntity","AppEnum","AppShortcutsProvider","AppShortcutProviding","EntityQuery","TransientEntity","DynamicOptionsProvider","AnyResolverProviding","AppIntentsPackage"]' \
  > "$temporary/protocols.json"
xcrun --sdk "$sdk" swiftc -target "$triple" -module-name "$module" -parse-as-library -c "$source_file" \
  -o "$temporary/intents.o" -module-cache-path "$temporary/module-cache" \
  -emit-const-values-path "$temporary/intents.swiftconstvalues" \
  -Xfrontend -const-gather-protocols-file -Xfrontend "$temporary/protocols.json"
printf '%s\n' "$source_file" > "$temporary/sources.txt"
printf '%s\n' "$temporary/intents.swiftconstvalues" > "$temporary/constvalues.txt"

mkdir "$temporary/out"
xcrun appintentsmetadataprocessor --output "$temporary/out" \
  --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")" \
  --module-name "$module" --sdk-root "$(xcrun --sdk "$sdk" --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
  --platform-family iOS --deployment-target 17.0 --target-triple "$triple" \
  --source-file-list "$temporary/sources.txt" --swift-const-vals-list "$temporary/constvalues.txt" \
  --compile-time-extraction --deployment-aware-processing --validate-assistant-intents --no-app-shortcuts-localization
[[ -f "$temporary/out/Metadata.appintents/extract.actionsdata" ]] || fail "The processor extracted no App Intents"
rm -rf "$app/Metadata.appintents"
mv "$temporary/out/Metadata.appintents" "$app/Metadata.appintents"
