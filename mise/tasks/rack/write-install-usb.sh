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
#   mise run rack:write-install-usb <disk> [--node <node>] [--ssh-key <pubkey>]
#   e.g. mise run rack:write-install-usb /dev/disk4 --node ber1-edge
#
# With --node the node's autoinstall config is baked into the image, so the
# machine installs itself with no keystrokes: no GRUB editing and nothing served
# over the network at boot. Without it you get a plain installer stick and the
# config has to come from mise run rack:install-node.
#
# Run it with no disk to list the external disks attached. Writing is
# destructive and asks for confirmation, then for sudo.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
release="$(jq -r '.ubuntu_release' "$root/infra/rack-nodes/nodes.json")"
disk=""
node=""
ssh_key="$HOME/.ssh/id_ed25519.pub"

while (( $# )); do
  case "$1" in
    --node) node="${2:-}"; shift 2;;
    --ssh-key) ssh_key="${2:-}"; shift 2;;
    -*) echo "unknown flag: $1" >&2; exit 2;;
    *) disk="$1"; shift;;
  esac
done

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

# shellcheck source=/dev/null
source "$root/infra/rack-nodes/ubuntu-iso.sh"
iso="$(ensure_ubuntu_iso "$release")"
echo "$(basename "$iso") verified against Ubuntu's SHA256SUMS"

image="$iso"
if [ -n "$node" ]; then
  if ! jq -e --arg n "$node" '.nodes[$n]' "$root/infra/rack-nodes/nodes.json" >/dev/null; then
    echo "error: unknown node '$node'" >&2
    echo "known nodes: $(jq -r '.nodes | keys | join(", ")' "$root/infra/rack-nodes/nodes.json")" >&2
    exit 2
  fi
  # shellcheck source=/dev/null
  source "$root/infra/rack-nodes/build-autoinstall-iso.sh"
  image="${iso%.iso}-$node.iso"
  rm -f "$image"
  build_autoinstall_iso "$node" "$iso" "$image" "$ssh_key"
  echo "$(basename "$image") built: installs $node unattended"
fi

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
sudo dd if="$image" of="$raw" bs=4m
sync
diskutil eject "$disk"

echo
echo
if [ -n "$node" ]; then
  echo "done. Boot $node from this stick and leave it alone; it installs itself"
  echo "and reboots into a machine reachable by SSH key."
else
  echo "done. Boot the node from this stick, then run:"
  echo "    mise run rack:install-node <node>"
fi
