#!/usr/bin/env bash
set -euo pipefail

[[ $# = 1 ]] || { echo 'Usage: fetch-sparkle.sh <new SDK directory>' >&2; exit 2; }
version=2.10.1
sha256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
output=$1
[[ ! -e "$output" && ! -L "$output" ]] || { echo 'SDK destination must be new' >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$tmp/Sparkle.tar.xz"
printf '%s  %s\n' "$sha256" "$tmp/Sparkle.tar.xz" | shasum -a 256 --check
mkdir "$tmp/sdk"
tar -xf "$tmp/Sparkle.tar.xz" -C "$tmp/sdk"
[[ -x "$tmp/sdk/bin/generate_appcast" && -x "$tmp/sdk/bin/sign_update" ]] || {
    echo 'Sparkle publishing tools are missing' >&2; exit 1;
}
ln -s Versions/Current/_CodeSignature "$tmp/sdk/Sparkle.framework/_CodeSignature"
mkdir -p "$(dirname "$output")"
mv "$tmp/sdk" "$output"
echo "Fetched Sparkle $version"
