#!/usr/bin/env bash
# Ubuntu 22.04 has no minisign package. Use the pinned upstream static binary.
set -euo pipefail
destination=${1:?Usage: install-minisign.sh DESTINATION}
test "$(uname -s)-$(uname -m)" = Linux-x86_64 || {
    printf 'This installer requires Linux x86_64\n' >&2
    exit 1
}
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
curl --fail --silent --show-error --location \
    https://github.com/jedisct1/minisign/releases/download/0.12/minisign-0.12-linux.tar.gz \
    --output "$temp/minisign.tar.gz"
printf '%s  %s\n' 9a599b48ba6eb7b1e80f12f36b94ceca7c00b7a5173c95c3efc88d9822957e73 "$temp/minisign.tar.gz" | sha256sum --check
tar -xzf "$temp/minisign.tar.gz" -C "$temp" minisign-linux/x86_64/minisign
mkdir -p "$destination"
install -m 755 "$temp/minisign-linux/x86_64/minisign" "$destination/minisign"
