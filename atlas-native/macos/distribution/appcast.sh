#!/usr/bin/env bash
# Vault credentials must never enter inherited shell tracing or verbose output.
set +x +v
set -euo pipefail
umask 077

[[ ( $# = 4 || $# = 5 ) && $3 =~ ^[1-9][0-9]{9,}$ ]] || {
    echo 'Usage: appcast.sh <Sparkle SDK> <release directory> <epoch build> <new feed.xml> [previous feed.xml]' >&2; exit 2;
}
sdk=$(cd "$1" && pwd)
release=$(cd "$2" && pwd)
build=$3
output=$4
previous=${5:-}
fail() { echo "$*" >&2; exit 1; }
[[ -x "$sdk/bin/generate_appcast" ]] || fail 'Missing Sparkle appcast generator'
[[ ! -e "$output" && ! -L "$output" ]] || fail 'Feed destination must be new'
[[ -f "$release/Atlas-macos.zip" ]] || fail 'Missing final Atlas archive'
(cd "$release" && shasum -a 256 --check SHASUMS256.txt)
archive_hash=$(shasum -a 256 "$release/Atlas-macos.zip")
length=$(stat -f %z "$release/Atlas-macos.zip")
namespace=http://www.andymatuschak.org/xml-namespaces/sparkle
version="*[local-name()='version' and namespace-uri()='$namespace']"
signature="@*[local-name()='edSignature' and namespace-uri()='$namespace']"

if [[ -n "$previous" ]]; then
    /usr/bin/xmllint --nonet --noout "$previous"
    [[ $(/usr/bin/xmllint --nonet --xpath 'count(/rss/channel)' "$previous") = 1 ]] || fail 'Invalid previous appcast'
    count=$(/usr/bin/xmllint --nonet --xpath 'count(/rss/channel/item)' "$previous")
    for ((index = 1; index <= count; index++)); do
        old=$(/usr/bin/xmllint --nonet --xpath "string(/rss/channel/item[$index]/$version)" "$previous")
        [[ "$old" =~ ^[1-9][0-9]{9,}$ ]] || fail 'Previous appcast has a non-epoch build'
        [[ ${#build} -gt ${#old} || ( ${#build} -eq ${#old} && "$build" > "$old" ) ]] || fail 'Build must exceed every published Atlas build'
    done
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/updates"
cp "$release/Atlas-macos.zip" "$tmp/updates/Atlas-macos.zip"
feed="$tmp/updates/atlas-appcast.xml"
if [[ -n "$previous" ]]; then cp "$previous" "$feed"; fi
prefix="https://github.com/tuist/tuist/releases/download/atlas-macos@$build/"
# Sparkle can move old archives; it must never operate on publication artifacts.
# Both providers can echo private key material in diagnostics, including failures.
if ! {
    op read 'op://tuist/Tuist App Private Sparkle Key/credential' | "$sdk/bin/generate_appcast" \
        --ed-key-file - --link https://github.com/tuist/tuist/releases \
        --download-url-prefix "$prefix" -o "$feed" "$tmp/updates"
} > "$tmp/appcast.log" 2>&1; then
    fail 'Could not sign the Atlas appcast (private diagnostics withheld)'
fi

/usr/bin/xmllint --nonet --noout "$feed"
item="/rss/channel/item[$version='$build']"
[[ $(/usr/bin/xmllint --nonet --xpath "count($item)" "$feed") = 1 ]] || fail 'Expected exactly one new Atlas build'
[[ $(/usr/bin/xmllint --nonet --xpath "count($item/enclosure)" "$feed") = 1 ]] || fail 'Expected one full update enclosure'
[[ $(/usr/bin/xmllint --nonet --xpath "string($item/enclosure/@url)" "$feed") = "${prefix}Atlas-macos.zip" ]] || fail 'Unexpected update URL'
[[ $(/usr/bin/xmllint --nonet --xpath "string($item/enclosure/@length)" "$feed") = "$length" ]] || fail 'Unexpected archive byte length'
signed=$(/usr/bin/xmllint --nonet --xpath "string($item/enclosure/$signature)" "$feed")
[[ "$signed" =~ ^[A-Za-z0-9+/]{86}==$ ]] || fail 'Missing or malformed Ed25519 archive signature'
[[ $(shasum -a 256 "$release/Atlas-macos.zip") = "$archive_hash" ]] || fail 'Appcast generation changed the release archive'
(cd "$release" && shasum -a 256 --check SHASUMS256.txt)
mkdir -p "$(dirname "$output")"
mv "$feed" "$output"
echo "Created signed Atlas appcast for build $build"
