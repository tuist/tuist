#!/usr/bin/env bash
#MISE description="Write an install stick that turns a rack Linux host into a cluster node with no keystrokes"
#
# The stick installs Ubuntu unattended and the installed machine joins the
# tailnet by itself on first boot, with a single-use join key minted now. The
# operator in the rack's cluster then finds it there and joins it as a node.
# The host has to be declared in rackLinuxFleet.hosts of the env's values.
#
# Usage:
#   mise run rack:write-install-usb <disk> --host <name> [--env <env>] [--key-hours 24] [--ssh-key <pubkey>]
#   mise run rack:write-install-usb --host <name> --output <iso>
#   mise run rack:write-install-usb <disk> --any-host [--env <env>]
#   mise run rack:write-install-usb --preinstall --output tuist_preinstall_<date>.iso [--internet-server <url>]
#
# Run it with no disk and no --output to list the external disks attached.
# Writing asks for confirmation, then for sudo. A stick installs a machine once:
# booted again, it hands over to the system it installed. Until the install has
# used it, the stick is a credential: a lost one is revoked by deleting its key
# (the ID is printed below) in the Tailscale admin console.
#
# --env defaults to the env the rack is in: the namespace its site definition
# (infra/rack-switch-fleet/sites/<site>.json, --site, default ber1) names.
#
# --any-host writes the stick that stays in every rack host instead: it carries
# no host's install and no credential, and installs whatever the env's boot
# server publishes for the machine it boots, whenever the operator boots it.
#
# --preinstall writes the image a server vendor boots once on a new box: it
# writes the --any-host installer onto the box's boot drive, so the box
# arrives carrying it. That installer also asks --internet-server, the boot
# server a box reaches before its site has one, and tries each site's static
# WAN. It carries no credential. See "The preinstall image" in
# infra/rack-nodes/AGENTS.md.
#
# See infra/rack-nodes/AGENTS.md.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
disk=""
host=""
any_host=""
preinstall=""
internet_server=""
env=""
site="${RACK_SITE:-ber1}"
key_hours=24
output=""
ssh_key="$HOME/.ssh/id_ed25519.pub"

while (( $# )); do
  case "$1" in
    --host) host="${2:-}"; shift 2;;
    --any-host) any_host=1; shift;;
    --preinstall) preinstall=1; shift;;
    --internet-server) internet_server="${2:-}"; shift 2;;
    --env) env="${2:-}"; shift 2;;
    --site) site="${2:-}"; shift 2;;
    --key-hours) key_hours="${2:-}"; shift 2;;
    --output) output="${2:-}"; shift 2;;
    --ssh-key) ssh_key="${2:-}"; shift 2;;
    -*) echo "unknown flag: $1" >&2; exit 2;;
    *) disk="$1"; shift;;
  esac
done

if [ -z "$disk" ] && [ -z "$output" ]; then
  echo "usage: mise run rack:write-install-usb <disk> (--host <name> | --any-host) [--env <env>]" >&2
  echo >&2
  echo "external disks attached:" >&2
  diskutil list external physical >&2 || echo "  none" >&2
  exit 2
fi
if [ -n "$host" ] && [ -n "$any_host" ]; then
  echo "error: --host and --any-host exclude each other" >&2
  exit 2
fi
if [ -n "$preinstall" ]; then
  [ -z "$host$any_host$disk" ] || { echo "error: --preinstall writes an image for a vendor, with --output alone" >&2; exit 2; }
  [ -n "$output" ] || { echo "error: --preinstall needs --output" >&2; exit 2; }
  case "$(basename "$output")" in
    *[!A-Za-z0-9_.]*|.*) echo "error: a BMC mounts an image whose name is letters, digits and underscores ending .iso: $output" >&2; exit 2;;
  esac
fi
[ -n "$preinstall" ] || [ -n "$host" ] || [ -n "$any_host" ] || { echo "error: --host names the rack host to install, or --any-host writes the stick every host keeps" >&2; exit 2; }
[[ "$key_hours" =~ ^[1-9][0-9]*$ ]] || { echo "error: --key-hours takes a whole number of hours" >&2; exit 2; }
if [ -n "$disk" ]; then
  case "$disk" in
    /dev/disk[0-9]*) ;;
    *) echo "error: expected a whole disk such as /dev/disk4, got '$disk'" >&2; exit 2;;
  esac
  if ! diskutil info "$disk" | grep -q "Removable Media:.*Removable"; then
    echo "error: $disk is not removable media. Refusing to write to it." >&2
    exit 1
  fi
fi
if ! command -v go >/dev/null; then
  echo "error: go renders the seed (brew install go)" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$root/infra/rack-nodes/host.sh"
# shellcheck source=/dev/null
source "$root/infra/rack-nodes/tailnet-key.sh"
# shellcheck source=/dev/null
source "$root/infra/rack-nodes/render-autoinstall.sh"
# shellcheck source=/dev/null
source "$root/infra/rack-nodes/build-autoinstall-iso.sh"
# shellcheck source=/dev/null
source "$root/infra/rack-nodes/ubuntu-iso.sh"
# shellcheck source=/dev/null
source "$root/infra/rack-switch-fleet/lib/config.sh"

if [ -z "$env" ]; then
  site_file="$(fleet_site_file "$site")"
  [ -f "$site_file" ] || { echo "error: no site definition at $site_file" >&2; exit 2; }
  env="$(fleet_site_env "$site_file")" || exit 2
  echo "the rack $site is in $env; writing a stick for $env"
fi

confirm_erase() {
  [ -n "$disk" ] || return 0
  echo
  diskutil info "$disk" | grep -E "Device Node|Volume Name|Disk Size|Device / Media Name" || true
  echo
  echo "This ERASES $disk completely."
  read -r -p "Type the disk name to continue ($disk): " confirm
  if [ "$confirm" != "$disk" ]; then
    echo "aborted" >&2
    exit 1
  fi
}

write_image() {
  diskutil unmountDisk "$disk"
  echo "writing (a few minutes; Ctrl-T shows progress)"
  sudo dd if="$1" of="${disk/\/dev\/disk//dev/rdisk}" bs=4m
  sync
  diskutil eject "$disk"
}

release=24.04

if [ -n "$preinstall" ]; then
  servers="$(rack_boot_server "$env")"
  if [ -n "$internet_server" ]; then
    [[ "$internet_server" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || { echo "error: --internet-server is https://<host>, got '$internet_server'" >&2; exit 2; }
    servers="$servers,$internet_server"
  fi
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT
  rack_site_wans >"$workdir/wans"
  render_preinstall_seeds "$workdir/seeds" "$servers" "$workdir/wans"
  (cd "$root/infra/cluster-api-provider-tuist" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o "$workdir/rack-node" ./cmd/rack-node)
  iso="$(ensure_ubuntu_iso "$release")"
  echo "$(basename "$iso") verified against Ubuntu's SHA256SUMS"
  build_preinstall_iso "$iso" "$output" "$workdir/seeds" "$workdir/rack-node"
  (cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")" >"$(basename "$output").sha256")
  cat <<EOF
wrote $output and $output.sha256:
$(cat "$output.sha256")
Booted once on a box, it writes the installer partition to its boot drive and
powers off. The installer asks $servers for the box's install
and tries the static WANs of: $(cut -d' ' -f1 "$workdir/wans" | tr '\n' ' ')
EOF
  exit 0
fi

if [ -n "$any_host" ]; then
  server="$(rack_boot_server "$env")"
  confirm_erase
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT
  render_stick_seed "$workdir/seed" "$server"
  iso="$(ensure_ubuntu_iso "$release")"
  echo "$(basename "$iso") verified against Ubuntu's SHA256SUMS"
  image="$workdir/tuist-install-$env.iso"
  build_autoinstall_iso "$iso" "$image" "$workdir/seed"
  if [ -n "$output" ]; then
    cp "$image" "$output"
    echo "wrote $output: it installs whatever $server publishes for the machine it boots"
    exit 0
  fi
  write_image "$image"
  cat <<EOF

Done. Plug this stick into a rack host of $env and leave it there. A host with
an empty disk boots it by itself, and the operator boots it once to reinstall a
running one. Its installer asks $server for the install
published for the machine, and waits until there is one. Watch it with:

  kubectl get racklinuxhost -w
EOF
  exit 0
fi

host_json="$(rack_host_json "$env" "$host")"
vault="$(jq -r '.vault' <<<"$host_json")"
ssh_item="$(jq -r '.sshItem' <<<"$host_json")"
tailscale_item="$(jq -r '.tailscaleItem' <<<"$host_json")"
[ -n "$ssh_item" ] || { echo "error: rackLinuxFleet.sshExternalSecret.item is not set for $env" >&2; exit 2; }
[ -n "$tailscale_item" ] || { echo "error: rackLinuxFleet.tailscale.externalSecret.item is not set for $env" >&2; exit 2; }

confirm_erase

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# The fleet key is the operator's way in; the writer's own key is a human's.
op read "op://$vault/$ssh_item/public-key" >"$workdir/authorized_keys"
echo >>"$workdir/authorized_keys"
if [ -f "${ssh_key/#\~/$HOME}" ]; then
  cat "${ssh_key/#\~/$HOME}" >>"$workdir/authorized_keys"
fi

# The account's password is a console login of last resort, kept in 1Password.
console_item="$host console"
if ! op item get "$console_item" --vault "$vault" >/dev/null 2>&1; then
  # shellcheck disable=SC2054  # commas belong to op's own flag values
  op item create --category=login "--title=$console_item" --vault "$vault" \
    --generate-password=letters,digits,24 --tags=rack,node \
    "username=$(jq -r '.sshUser' <<<"$host_json")" >/dev/null
fi
( umask 077; op read "op://$vault/$console_item/password" >"$workdir/console-password" )

tags="$(jq -c '.tailnetTags' <<<"$host_json")"
minted="$(mint_tailnet_key "$vault" "$tailscale_item" "$tags" "$key_hours" "$host")"
key_id="${minted%%$'\t'*}"
( umask 077; printf '%s\n' "${minted#*$'\t'}" >"$workdir/tailnet-key" )
unset minted
echo "minted tailnet key $key_id: single-use, tagged $tags, expires in ${key_hours}h"

render_autoinstall "$workdir/seed" "$host_json" "$workdir/console-password" "$workdir/authorized_keys" "$workdir/tailnet-key" "$key_id"

iso="$(ensure_ubuntu_iso "$release")"
echo "$(basename "$iso") verified against Ubuntu's SHA256SUMS"
image="$workdir/$host.iso"
build_autoinstall_iso "$iso" "$image" "$workdir/seed"

if [ -n "$output" ]; then
  ( umask 077; cp "$image" "$output" )
  echo "wrote $output: it carries tailnet key $key_id until the install uses it"
  exit 0
fi

write_image "$image"

cat <<EOF

Done. Boot $host from this stick and leave it: it installs itself, reboots,
joins the tailnet with key $key_id, and the cluster's operator joins it as a
node. Pull the stick once the node is up. Watch it with:

  kubectl get racklinuxhost $host -w
  kubectl get racklinuxmachine -o wide
EOF
