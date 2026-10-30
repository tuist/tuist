#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $# = 2 ]] || { echo 'Usage: test-appcast.sh <Sparkle SDK> <prepared Atlas.app>' >&2; exit 2; }
sdk=$(cd "$1" && pwd)
app=$(cd "$2" && pwd)
scripts=$(cd "$(dirname "$0")" && pwd)
[[ -x "$sdk/bin/sign_update" && -f "$app/Contents/Info.plist" ]] || exit 1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
export ATLAS_TEST_SEED="$tmp/seed" ATLAS_TEST_READS="$tmp/key-reads"
cat > "$tmp/bin/op" <<'BASH'
#!/bin/bash
set -euo pipefail
[[ $# = 2 && $1 = read && $2 = 'op://tuist/Tuist App Private Sparkle Key/credential' ]] || exit 1
echo read >> "$ATLAS_TEST_READS"
cat "$ATLAS_TEST_SEED"
BASH
chmod +x "$tmp/bin/op"
export PATH="$tmp/bin:$PATH"

# CryptoKit creates disposable keys without reading or writing any Keychain.
cat > "$tmp/keys.swift" <<'SWIFT'
import CryptoKit
import Foundation

let args = CommandLine.arguments
if args[1] == "generate" {
    let key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.base64EncodedString().write(toFile: args[2], atomically: true, encoding: .utf8)
    try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: args[3], atomically: true, encoding: .utf8)
} else {
    let publicBytes = Data(base64Encoded: try String(contentsOfFile: args[2], encoding: .utf8))!
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
    let bytes = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    let signature = Data(base64Encoded: args[4])!
    exit(key.isValidSignature(signature, for: bytes) ? 0 : 1)
}
SWIFT
xcrun swiftc "$tmp/keys.swift" -o "$tmp/keys"
"$tmp/keys" generate "$tmp/seed" "$tmp/public"
"$tmp/keys" generate "$tmp/wrong-seed" "$tmp/wrong-public"
cp "$app/Contents/Info.plist" "$tmp/original.plist"
previous=()
for build in 1800000000 1800000001; do
    release="$tmp/$build"
    mkdir "$release"
    ditto "$app" "$release/Atlas.app"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$release/Atlas.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $(cat "$tmp/public")" "$release/Atlas.app/Contents/Info.plist"
    codesign --force --sign - --timestamp=none --options 0 "$release/Atlas.app"
    ditto -c -k --sequesterRsrc --keepParent "$release/Atlas.app" "$release/Atlas-macos.zip"
    (cd "$release" && shasum -a 256 Atlas-macos.zip > SHASUMS256.txt)
    bash "$scripts/appcast.sh" "$sdk" "$release" "$build" "$release/atlas-appcast.xml" ${previous[@]+"${previous[@]}"}
    signature=$(/usr/bin/xmllint --nonet --xpath \
        "string(/rss/channel/item[*[local-name()='version']='$build']/enclosure/@*[local-name()='edSignature'])" "$release/atlas-appcast.xml")
    "$tmp/keys" verify "$tmp/public" "$release/Atlas-macos.zip" "$signature"
    "$sdk/bin/sign_update" --verify --ed-key-file "$tmp/seed" "$release/Atlas-macos.zip" "$signature"
    if "$sdk/bin/sign_update" --verify --ed-key-file "$tmp/wrong-seed" "$release/Atlas-macos.zip" "$signature" > "$tmp/wrong-key.log" 2>&1; then
        echo 'Wrong signing key was accepted' >&2; exit 1
    fi
    cp "$release/Atlas-macos.zip" "$tmp/altered.zip"
    printf 'altered' >> "$tmp/altered.zip"
    if "$tmp/keys" verify "$tmp/public" "$tmp/altered.zip" "$signature"; then
        echo 'Altered archive was accepted' >&2; exit 1
    fi
    (cd "$release" && shasum -a 256 --check SHASUMS256.txt)
    previous=("$release/atlas-appcast.xml")
    echo "Verified build $build with real Sparkle and independent CryptoKit signatures"
done
[[ $(/usr/bin/xmllint --nonet --xpath 'count(/rss/channel/item)' "${previous[0]}") = 2 ]]
[[ $(/usr/bin/xmllint --nonet --xpath \
    "string(/rss/channel/item[*[local-name()='version']='1800000000']/enclosure/@url)" "${previous[0]}") = \
    https://github.com/tuist/tuist/releases/download/atlas-macos@1800000000/Atlas-macos.zip ]]
reads=$(wc -l < "$tmp/key-reads")
for build in 1800000000 1800000001; do
    if bash "$scripts/appcast.sh" "$sdk" "$release" "$build" "$tmp/rejected-$build.xml" "${previous[0]}" > "$tmp/rejected.log" 2>&1; then
        echo 'Equal or older build was accepted' >&2; exit 1
    fi
    [[ ! -e "$tmp/rejected-$build.xml" ]]
done
[[ $(wc -l < "$tmp/key-reads") = "$reads" ]]
cmp "$app/Contents/Info.plist" "$tmp/original.plist"
echo 'Real Sparkle appcast checks passed (successive builds, retained history, authentic signatures, tamper/wrong-key rejection and untouched source)'
