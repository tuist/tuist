#!/usr/bin/env bash
#MISE description="Serve a BER1 rack node's unattended Ubuntu install config to the machine being built"
#
# The rack's x86 nodes install themselves: Ubuntu's installer reads an
# autoinstall config, so a node is defined by a file in this repo rather than by
# what someone clicked. This renders the config for a node from
# infra/rack-nodes/nodes.json, serves it over HTTP, and prints the one line to
# type at the installer's boot menu.
#
# Ubuntu 24.04 LTS matches the rest of the fleet: every Linux machine, rented or
# owned, runs the stock distro converged after first boot, and there is no image
# to build.
#
# Usage:
#   mise run rack:install-node <node> [--serve-iso] [--ssh-key <pubkey>] [--port <port>]
#   e.g. mise run rack:install-node ber1-edge --serve-iso
#
# With --serve-iso it also serves the Ubuntu installer image, so a machine with a
# KVM needs no USB stick at all: mount the printed ISO URL as virtual media (the
# KVM streams it to the target as a USB drive) and boot from it. Without the
# flag, boot from a stick written by mise run rack:write-install-usb.
#
# Either way, at the installer's GRUB menu press `e`, append the printed options
# to the `linux` line, and press Ctrl-X. The install then runs unattended and
# reboots into a machine reachable by SSH key only.
#
# See infra/rack-nodes/AGENTS.md for what the config sets and what is left to
# post-install convergence.

set -euo pipefail

node=""
ssh_key="$HOME/.ssh/id_ed25519.pub"
port=3003
serve_iso=0

while (( $# )); do
  case "$1" in
    --ssh-key) ssh_key="${2:-}"; shift 2;;
    --port) port="${2:-}"; shift 2;;
    --serve-iso) serve_iso=1; shift;;
    -*) echo "unknown flag: $1" >&2; exit 2;;
    *) node="$1"; shift;;
  esac
done

root="$(git rev-parse --show-toplevel)"
inventory="$root/infra/rack-nodes/nodes.json"

if [ -z "$node" ] || ! jq -e --arg n "$node" '.nodes[$n]' "$inventory" >/dev/null; then
  echo "usage: mise run rack:install-node <node> [--ssh-key <pubkey>] [--port <port>]" >&2
  echo "known nodes: $(jq -r '.nodes | keys | join(", ")' "$inventory")" >&2
  exit 2
fi

entry="$(jq -r --arg n "$node" '.nodes[$n]' "$inventory")"
role="$(jq -r '.role' <<<"$entry")"
install_user="$(jq -r '.install_user' "$inventory")"
release="$(jq -r '.ubuntu_release' "$inventory")"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# shellcheck source=/dev/null
source "$root/infra/rack-nodes/render-autoinstall.sh"
render_autoinstall "$node" "$workdir" "$ssh_key"

iso_name=""
if (( serve_iso )); then
  # shellcheck source=/dev/null
  source "$root/infra/rack-nodes/ubuntu-iso.sh"
  iso_path="$(ensure_ubuntu_iso "$release")"
  iso_name="$(basename "$iso_path")"
  ln -s "$iso_path" "$workdir/$iso_name"
fi

interface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
address="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
if [ -z "$address" ]; then
  echo "error: could not work out this machine's address on the rack network" >&2
  exit 1
fi

cat <<EOF

$node ($role), Ubuntu $release, unattended install
EOF

if (( serve_iso )); then
  cat <<EOF

In the KVM's Virtual Media, mount this URL and boot the node from it:

    http://$address:$port/$iso_name
EOF
fi

cat <<EOF

At the installer's GRUB menu press 'e', append this to the line starting 'linux',
then press Ctrl-X:

    autoinstall "ds=nocloud-net;s=http://$address:$port/"

Serving the config on http://$address:$port/ . The installer fetches it, wipes
the target disk without asking, installs, and reboots. Afterwards:

    ssh $install_user@<address it picks up by DHCP>

Leave this running until the install is done, then stop it with Ctrl-C.

EOF

cd "$workdir"
python3 -m http.server "$port" --bind "$address"
