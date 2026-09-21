#!/usr/bin/env bash
#MISE description="Write a verified Ubuntu Server install stick for the BER1 rack nodes"
#
# Downloads the current Ubuntu LTS server ISO for the release pinned in
# infra/rack-nodes/nodes.json, checks it against Ubuntu's published SHA256SUMS,
# and writes it to a USB stick. The ISO is cached, so the second stick costs
# nothing.
#
# The stick only carries the installer. What the machine becomes is decided by
# mise run rack:install-node, which serves the autoinstall config over the
# network, so one stick builds every node and nothing on it needs updating when
# a node's definition changes.
#
# Usage:
#   mise run rack:write-install-usb <disk>
#   e.g. mise run rack:write-install-usb /dev/disk4
#
# Run it with no disk to list the external disks attached. Writing is
# destructive and asks for confirmation, then for sudo.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
release="$(jq -r '.ubuntu_release' "$root/infra/rack-nodes/nodes.json")"
cache="${XDG_CACHE_HOME:-$HOME/Library/Caches}/tuist-rack"
base="https://releases.ubuntu.com/$release"

disk="${1:-}"

if [ -z "$disk" ]; then
  echo "usage: mise run rack:write-install-usb <disk>" >&2
  echo >&2
  echo "external disks attached:" >&2
  diskutil list external physical >&2 || echo "  none" >&2
  exit 2
fi

case "$disk" in
  /dev/disk[0-9]*) ;;
  *) echo "error: expected a whole disk such as /dev/disk4, got '$disk'" >&2; exit 2;;
esac

if ! diskutil info "$disk" | grep -q "Removable Media:.*Removable"; then
  echo "error: $disk is not removable media. Refusing to write to it." >&2
  exit 1
fi

mkdir -p "$cache"
sums="$cache/SHA256SUMS-$release"
curl -fsSL "$base/SHA256SUMS" -o "$sums"

iso_name="$(awk '/live-server-amd64\.iso$/{print $2}' "$sums" | tr -d '*' | head -1)"
if [ -z "$iso_name" ]; then
  echo "error: no live-server-amd64 ISO listed for Ubuntu $release" >&2
  exit 1
fi
iso="$cache/$iso_name"

if [ ! -f "$iso" ]; then
  echo "downloading $iso_name"
  curl -fL --progress-bar "$base/$iso_name" -o "$iso.partial"
  mv "$iso.partial" "$iso"
fi

expected="$(awk -v n="$iso_name" '$2 == "*"n || $2 == n {print $1}' "$sums" | head -1)"
actual="$(shasum -a 256 "$iso" | awk '{print $1}')"
if [ "$expected" != "$actual" ]; then
  echo "error: checksum mismatch for $iso_name" >&2
  echo "  expected $expected" >&2
  echo "  actual   $actual" >&2
  echo "  delete the cached file and retry" >&2
  exit 1
fi
echo "$iso_name verified against Ubuntu's SHA256SUMS"

echo
diskutil info "$disk" | grep -E "Device Node|Volume Name|Disk Size|Device / Media Name" || true
echo
echo "This ERASES $disk completely."
read -r -p "Type the disk name to continue ($disk): " confirm
if [ "$confirm" != "$disk" ]; then
  echo "aborted" >&2
  exit 1
fi

diskutil unmountDisk "$disk"
raw="${disk/\/dev\/disk//dev/rdisk}"
echo "writing (a few minutes; Ctrl-T shows progress)"
sudo dd if="$iso" of="$raw" bs=4m
sync
diskutil eject "$disk"

echo
echo "done. Boot the node from this stick, then run:"
echo "    mise run rack:install-node <node>"
