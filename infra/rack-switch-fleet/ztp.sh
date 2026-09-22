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
# to exactly one interface, with only the switch on the other end.
#
# It serves from this Mac, through a USB Ethernet adapter, or with --via from a
# Linux machine reached over SSH. The rack's edge node is the natural one: its
# management port is the cable ber1-mgmt hangs off in the real rack, and in a
# data center there is no laptop.
#
#   mise run rack:ztp <device> --interface en7 [--dry-run]
#   mise run rack:ztp <device> --via tuist@ber1-edge --interface enp89s0 [--dry-run]
#
# --create-credentials makes the switch's 1Password item if it has none yet, as
# rack:prep-switch does.
#
# See infra/rack-switch-fleet/AGENTS.md.

set -euo pipefail

FLEET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$FLEET_ROOT/lib/config.sh"

SITE="${RACK_SITE:-ber1}"
device=""
interface=""
via=""
dry_run=0
create_credentials=0

while (( $# )); do
  case "$1" in
    --interface) interface="${2:-}"; shift 2;;
    --site) SITE="${2:-}"; shift 2;;
    --via) via="${2:-}"; shift 2;;
    --dry-run) dry_run=1; shift;;
    --create-credentials) create_credentials=1; shift;;
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

# The interface name reaches a remote shell with --via.
if ! [[ "$interface" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "error: '$interface' is not an interface name" >&2
  exit 2
fi

# A command on whichever machine serves: this one, or the --via host.
on_server() {
  if [ -n "$via" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$via" "$1"
  else
    bash -c "$1"
  fi
}
server="${via:-this machine}"

# --- refuse to become a rogue DHCP server ------------------------------------

# A failing lookup must not end the run under pipefail before the guards below
# have said anything, hence the `|| true`s.
if [ -n "$via" ]; then
  default_interfaces="$(on_server "ip route show default | awk '{print \$5}'" 2>/dev/null || true)"
  on_server "ip link show dev $interface" >/dev/null 2>&1 || { echo "error: $server has no interface $interface" >&2; exit 1; }
  server_ip="$(on_server "ip -4 -o addr show dev $interface | awk '{print \$4}' | cut -d/ -f1 | head -1" 2>/dev/null || true)"
  address_hint="ssh $via 'sudo ip addr add 192.168.50.1/24 dev $interface && sudo ip link set $interface up'"
else
  default_interfaces="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' || true)"
  ifconfig "$interface" >/dev/null 2>&1 || { echo "error: no interface $interface" >&2; exit 1; }
  server_ip="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
  address_hint="sudo ifconfig $interface inet 192.168.50.1 netmask 255.255.255.0 up"
fi
if grep -qx -- "$interface" <<<"$default_interfaces"; then
  echo "error: $interface carries $server's default route, so it is a network people are" >&2
  echo "       on. Serving DHCP there would hand addresses to everything on it." >&2
  exit 1
fi
if [ -z "$server_ip" ]; then
  echo "error: $interface on $server has no IPv4 address, so there is nothing to serve from." >&2
  echo "       Give it one on the isolated segment first, for example:" >&2
  echo "         $address_hint" >&2
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

username="$(jq -r '.credentials.username' "$site_file")"

# A switch that has never been prepped has no item yet. --create-credentials
# makes one the way rack:prep-switch does; a dry run never creates anything.
password=""
if ! credentials="$(op item get "$credential_item" --vault "$vault" --format=json 2>/dev/null)"; then
  credentials=""
  if (( create_credentials && ! dry_run )); then
    # shellcheck disable=SC2054  # commas belong to op's own flag values
    op item create --category=login "--title=$credential_item" --vault "$vault" \
      --generate-password=letters,digits,24 "--tags=$SITE,rack,network" "username=$username" >/dev/null
    credentials="$(op item get "$credential_item" --vault "$vault" --format=json)"
  elif (( create_credentials )); then
    echo "note: no 1Password item '$credential_item'; a real run creates it"
    credentials='{"fields":[{"id":"password","value":"<redacted>"}]}'
  fi
fi
if [ -n "$credentials" ]; then
  password="$(jq -r '.fields[]? | select(.id == "password") | .value // empty' <<<"$credentials")"
fi
if [ -z "$password" ]; then
  echo "error: no password on the 1Password item '$credential_item'." >&2
  echo "       A switch provisioned from scratch has none of our credentials, so the config" >&2
  echo "       it fetches has to carry the login. --create-credentials makes the item." >&2
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

# With --via the files are copied to the server when serving starts, so the
# configuration names the directory they will be in there.
serve_root="$tftp_root"
if [ -n "$via" ]; then
  if (( dry_run )); then
    serve_root="<a temporary directory on $via>"
  else
    serve_root="$(on_server 'mktemp -d')"
  fi
fi
# dnsmasq drops root once its ports are bound, and the served directory is
# readable only by its owner because the file in it carries a password. So it
# drops to that owner rather than to nobody, who could read nothing here.
serve_user="$(on_server 'id -un')"

conf="$tftp_root/dnsmasq.conf"
subnet="${server_ip%.*}"
{
  echo "# generated by rack:ztp, do not edit"
  echo "port=0"                      # no DNS at all
  echo "interface=$interface"
  echo "bind-interfaces"
  echo "no-hosts"
  echo "no-resolv"
  echo "user=$serve_user"
  echo "dhcp-leasefile=$serve_root/dnsmasq.leases"
  echo "dhcp-authoritative"
  echo "dhcp-range=$subnet.100,$subnet.150,1h"
  echo "enable-tftp"
  echo "tftp-root=$serve_root"
  echo "dhcp-option=66,\"$server_ip\""
  echo "log-dhcp"
  if [ -n "$mac" ]; then
    # Only this switch gets an answer, so even a segment that turns out not to
    # be isolated hands nothing to anything else on it.
    echo "dhcp-host=$mac,set:$device"
    echo "dhcp-ignore=tag:!known"
    echo "dhcp-option=tag:$device,67,\"$boot_file\""
  else
    echo "# no mac in the site definition, so every client is offered this file"
    echo "dhcp-boot=$boot_file"
  fi
} > "$conf"

echo "interface     $interface on $server at $server_ip (default route on $(tr '\n' ' ' <<<"${default_interfaces:-none}"))"
echo "serving       $boot_file from $serve_root"
echo "to            ${mac:-any client on this segment}"
echo ""
echo "dnsmasq configuration:"
sed 's/^/  /' "$conf"
echo ""
echo "the switch would fetch (login line redacted):"
tr -d '\000' < "$served" | tr -d '\r' | sed "s/secret 0 .*/secret 0 <redacted>/" | head -20 | sed 's/^/  /'
echo "  ... $(tr -d '\000' < "$served" | grep -c '' ) lines"

cleanup() {
  rm -rf "$tftp_root" "$rendered"
  if [ -n "$via" ] && (( ! dry_run )); then on_server "rm -rf '$serve_root'" || true; fi
}

echo ""
install_hint="brew install dnsmasq"
[ -n "$via" ] && install_hint="ssh $via 'sudo apt-get install -y dnsmasq-base'"
if dnsmasq_path="$(on_server 'command -v dnsmasq' 2>/dev/null)"; then
  echo "dnsmasq   $dnsmasq_path on $server"
else
  dnsmasq_path=""
  echo "dnsmasq   NOT INSTALLED on $server: $install_hint"
fi

if (( dry_run )); then
  echo ""
  echo "dry run, nothing served. The files are in $tftp_root"
  exit 0
fi

[ -n "$dnsmasq_path" ] || {
  echo "error: dnsmasq is not installed on $server ($install_hint)" >&2
  cleanup
  exit 1
}

echo ""
echo "This serves DHCP on $interface on $server. Confirm nothing but the switch is on that segment."
if [ -t 0 ]; then
  read -r -p "start? [y/N] " answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ] || { cleanup; exit 130; }
fi

trap 'echo ""; echo "stopped; the served files are deleted"; cleanup' EXIT
if [ -n "$via" ]; then
  tar -C "$tftp_root" -cf - . | on_server "tar -C '$serve_root' -xf -"
fi
echo "serving; power the switch on with Auto Install armed. Ctrl-C to stop."
if [ -n "$via" ]; then
  # The server cleans up after itself the moment this SSH session is gone,
  # however this end died. Relying on a hangup was not enough: killed outright,
  # this end ran no trap, sudo's own terminal swallowed the hangup, and dnsmasq
  # kept serving on the rack with the password still on disk.
  ssh -o BatchMode=yes "$via" "sudo -n dnsmasq --conf-file='$serve_root/dnsmasq.conf' --no-daemon --log-facility=- & served=\$!
    session=\$PPID
    while ps -p \$session >/dev/null 2>&1 && ps -p \$served >/dev/null 2>&1; do sleep 2; done
    sudo -n kill \$served 2>/dev/null
    rm -rf '$serve_root'"
else
  sudo dnsmasq --conf-file="$conf" --no-daemon --log-facility=-
fi
