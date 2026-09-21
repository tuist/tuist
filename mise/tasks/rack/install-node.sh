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
#   mise run rack:install-node <node> [--ssh-key <pubkey>] [--port <port>]
#   e.g. mise run rack:install-node ber1-edge
#
# Boot the target from an install stick (mise run rack:write-install-usb), then
# at the GRUB menu press `e`, append the printed options to the `linux` line, and
# press Ctrl-X. The install runs unattended and reboots into a machine reachable
# by SSH key only.
#
# See infra/rack-nodes/AGENTS.md for what the config sets and what is left to
# post-install convergence.

set -euo pipefail

node=""
ssh_key="$HOME/.ssh/id_ed25519.pub"
port=3003

while (( $# )); do
  case "$1" in
    --ssh-key) ssh_key="${2:-}"; shift 2;;
    --port) port="${2:-}"; shift 2;;
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
layout="$(jq -r '.layout' <<<"$entry")"
role="$(jq -r '.role' <<<"$entry")"
install_user="$(jq -r '.install_user' "$inventory")"
release="$(jq -r '.ubuntu_release' "$inventory")"

if [ "$layout" = "storage" ]; then
  echo "error: the storage layout is not implemented yet." >&2
  echo "       Cluster nodes need /boot, a capped /, and a separate XFS /data with" >&2
  echo "       project quotas; the self-join refuses a machine that cannot enforce" >&2
  echo "       them, and partitioning cannot be changed afterwards. Work it out" >&2
  echo "       against controllers/linux/linux_cloudinit.go before installing $node." >&2
  exit 1
fi

ssh_key="${ssh_key/#\~/$HOME}"
if [ ! -f "$ssh_key" ]; then
  echo "error: no such public key: $ssh_key" >&2
  exit 1
fi
key_material="$(tr -d '\n' < "$ssh_key")"

# The account exists so the installer is happy and so there is a console login of
# last resort; it is never used over the network, where only the key is accepted.
password_hash="$(openssl passwd -6 "$(openssl rand -base64 24)")"
packages="$(jq -r '.packages | map("    - " + .) | join("\n")' <<<"$entry")"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

: > "$workdir/meta-data"
: > "$workdir/vendor-data"

cat > "$workdir/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: $node
    username: $install_user
    password: "$password_hash"
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - "$key_material"
  storage:
    layout:
      name: direct
  packages:
$packages
  updates: security
  shutdown: reboot
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
EOF

interface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
address="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
if [ -z "$address" ]; then
  echo "error: could not work out this machine's address on the rack network" >&2
  exit 1
fi

cat <<EOF

$node ($role), Ubuntu $release, unattended install

At the installer's GRUB menu press 'e', append this to the line starting 'linux',
then press Ctrl-X:

    autoinstall "ds=nocloud-net;s=http://$address:$port/"

Serving the config on http://$address:$port/ . The installer fetches it, wipes
the target disk without asking, installs, and reboots. Afterwards:

    ssh $install_user@<address it picks up by DHCP>

Leave this running until the install is done, then stop it with Ctrl-C.

EOF

cd "$workdir"
exec python3 -m http.server "$port" --bind "$address"
