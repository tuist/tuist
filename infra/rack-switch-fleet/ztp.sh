#!/usr/bin/env bash
#
# Zero-touch provisioning for a rack switch, on an isolated segment.
#
# A factory switch with Auto Install enabled boots, asks DHCP for an address and
# a boot file, fetches that file over TFTP and applies it. This serves both
# halves: dnsmasq for DHCP and TFTP, and the configuration rendered from the
# site definition.
#
# The dangerous part is not the switch, it is the DHCP server. A second DHCP
# server on a network people live on hands out addresses to laptops and phones,
# so this refuses to run on the interface carrying the default route and binds
# to exactly one interface. Use a USB Ethernet adapter with the switch on the
# other end and nothing else attached.
#
#   mise run rack:ztp <device> --interface en7 [--dry-run]
#
# See infra/rack-switch-fleet/AGENTS.md.

set -euo pipefail

FLEET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$FLEET_ROOT/lib/config.sh"

SITE="${RACK_SITE:-ber1}"
device=""
interface=""
dry_run=0

while (( $# )); do
  case "$1" in
    --interface) interface="${2:-}"; shift 2;;
    --site) SITE="${2:-}"; shift 2;;
    --dry-run) dry_run=1; shift;;
    -*) echo "unknown flag: $1" >&2; exit 2;;
    *) device="$1"; shift;;
  esac
done

site_file="$(fleet_site_file "$SITE")"
[ -f "$site_file" ] || { echo "error: no site definition at $site_file" >&2; exit 2; }
[ -n "$device" ] || { echo "usage: mise run rack:ztp <device> --interface <iface> [--dry-run]" >&2; exit 2; }
[ -n "$interface" ] || {
  echo "error: --interface is required, and it must be an isolated segment." >&2
  echo "       Use a USB Ethernet adapter with only the switch on it. This serves DHCP," >&2
  echo "       and a second DHCP server on a network with people on it hands addresses" >&2
  echo "       to their laptops." >&2
  exit 2
}

entry="$(fleet_device "$site_file" "$device")"
mac="$(jq -r '.mac // empty' <<<"$entry")"
credential_item="$(jq -r '.credential_item' <<<"$entry")"
vault="$(jq -r '.credentials.vault' "$site_file")"

# --- refuse to become a rogue DHCP server ------------------------------------

# `route -n get` is macOS; elsewhere it fails, and under pipefail that must not
# end the run before the guards below have said anything.
default_interface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' || true)"
if [ "$interface" = "$default_interface" ]; then
  echo "error: $interface carries this machine's default route, so it is the network you" >&2
  echo "       are on. Serving DHCP there would hand addresses to everything on it." >&2
  exit 1
fi
if ! ifconfig "$interface" >/dev/null 2>&1; then
  echo "error: no interface $interface" >&2
  exit 1
fi
server_ip="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
if [ -z "$server_ip" ]; then
  echo "error: $interface has no IPv4 address, so there is nothing to serve from." >&2
  echo "       Give it one on the isolated segment first, for example:" >&2
  echo "         sudo ifconfig $interface inet 192.168.50.1 netmask 255.255.255.0 up" >&2
  exit 1
fi

# --- the configuration the switch will fetch ---------------------------------
#
# A factory switch has none of our credentials, so unlike `replace`, which
# carries the login across from the switch itself, this has to put one in. It
# goes in as `secret 0 <password>`, which the switch hashes itself, so the only
# credential is the password already in the switch's 1Password item. The dry run
# writes it redacted, and a real run deletes the served files once it stops.

boot_file="$device.cfg"

# The fleet key is not configuration either: prep-switch installs it with a
# download command, and no export carries it. Without it the switch comes up
# with a password login the fleet tools cannot use.
public_key="$(jq -r '.credentials.ssh_key' "$site_file")"
public_key="${public_key/#\~/$HOME}.pub"
if [ ! -f "$public_key" ]; then
  echo "error: no fleet public key at $public_key" >&2
  exit 1
fi
if grep -q 'ssh-ed25519' "$public_key"; then
  echo "error: $public_key is ed25519, which this firmware rejects; use an RSA key" >&2
  exit 1
fi

password=""
if credentials="$(op item get "$credential_item" --vault "$vault" --format=json 2>/dev/null)"; then
  password="$(jq -r '.fields[]? | select(.id == "password") | .value // empty' <<<"$credentials")"
fi
if [ -z "$password" ]; then
  echo "error: no password on the 1Password item '$credential_item'." >&2
  echo "       A switch provisioned from scratch has none of our credentials, so the config" >&2
  echo "       it fetches has to carry the login." >&2
  exit 1
fi
# The switch's own limits for `secret 0`. Anything else would be rejected and
# leave the switch with no login of ours.
if ! [[ "$password" =~ ^[^[:space:]\"?]{6,31}$ ]]; then
  echo "error: the password on '$credential_item' is not one the switch accepts: 6 to 31" >&2
  echo "       characters, no spaces, question marks or double quotes." >&2
  exit 1
fi
(( dry_run )) && password="<redacted>"

tftp_root="$(mktemp -d)"
rendered="$(mktemp)"
fleet_render "$site_file" "$device" > "$rendered"
# RFC4716, the only form the switch accepts.
if head -1 "$public_key" | grep -q 'BEGIN SSH2'; then
  cp "$public_key" "$tftp_root/fleet.pub"
else
  ssh-keygen -e -f "$public_key" > "$tftp_root/fleet.pub"
fi

username="$(jq -r '.credentials.username' "$site_file")"
served="$tftp_root/$boot_file"
# Both go ahead of `telnet disable`, which is where a prepped switch keeps the
# login. For the key that position also matters: the download has to run while
# the switch still holds its DHCP address on this segment, and the file moves it
# to its site address further down, at `interface vlan`.
{
  awk -v login="user name $username privilege admin secret 0 $password" \
      -v key="ip ssh download v2 fleet.pub ip-address $server_ip" '
    $0 ~ /^telnet / && !done { print login; print "ip ssh server"; print key; done = 1 } { print }' "$rendered"
} | fleet_device_file > "$served"

# --- dnsmasq: DHCP and TFTP, and deliberately no DNS -------------------------

conf="$tftp_root/dnsmasq.conf"
subnet="${server_ip%.*}"
{
  echo "# generated by rack:ztp, do not edit"
  echo "port=0"                      # no DNS at all
  echo "interface=$interface"
  echo "bind-interfaces"
  echo "except-interface=lo0"
  echo "no-hosts"
  echo "no-resolv"
  echo "dhcp-authoritative"
  echo "dhcp-range=$subnet.100,$subnet.150,1h"
  echo "enable-tftp"
  echo "tftp-root=$tftp_root"
  echo "dhcp-option=66,\"$server_ip\""
  echo "log-dhcp"
  if [ -n "$mac" ]; then
    echo "dhcp-host=$mac,set:$device"
    echo "dhcp-option=tag:$device,67,\"$boot_file\""
  else
    echo "# no mac in the site definition, so every client is offered this file"
    echo "dhcp-boot=$boot_file"
  fi
} > "$conf"

echo "interface     $interface at $server_ip (default route is on ${default_interface:-none})"
echo "serving       $boot_file from $tftp_root"
echo "to            ${mac:-any client on this segment}"
echo ""
echo "dnsmasq configuration:"
sed 's/^/  /' "$conf"
echo ""
echo "the switch would fetch (login line redacted):"
tr -d '\000' < "$served" | tr -d '\r' | sed "s/secret 0 .*/secret 0 <redacted>/" | head -20 | sed 's/^/  /'
echo "  ... $(tr -d '\000' < "$served" | grep -c '' ) lines"

echo ""
if command -v dnsmasq >/dev/null 2>&1; then
  echo "dnsmasq   $(command -v dnsmasq)"
else
  echo "dnsmasq   NOT INSTALLED: brew install dnsmasq"
fi

if (( dry_run )); then
  echo ""
  echo "dry run, nothing served. The files are in $tftp_root"
  exit 0
fi

command -v dnsmasq >/dev/null 2>&1 || {
  echo "error: dnsmasq is not installed (brew install dnsmasq)" >&2
  rm -rf "$tftp_root" "$rendered"
  exit 1
}

echo ""
echo "This serves DHCP on $interface. Confirm nothing but the switch is on that segment."
if [ -t 0 ]; then
  read -r -p "start? [y/N] " answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ] || { rm -rf "$tftp_root" "$rendered"; exit 130; }
fi

echo "serving; power the switch on with Auto Install armed. Ctrl-C to stop."
trap 'echo ""; echo "stopped; the served files are deleted"; rm -rf "$tftp_root" "$rendered"' EXIT
sudo dnsmasq --conf-file="$conf" --no-daemon --log-facility=-
