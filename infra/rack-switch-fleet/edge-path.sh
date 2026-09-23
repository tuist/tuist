#!/usr/bin/env bash
#
# The path from the switches' management addresses to the tailnet, through the
# rack's edge node. Every switch in the site reaches the Omada controller, which
# lives in a cluster on the tailnet, by a static route to the tailnet's range
# via the edge node's address; the edge node forwards that traffic into
# tailscale0, translated to its own tailnet address. A switch marked
# `behind_edge` hangs off one of the edge node's own ports, so it also gets a
# host route there; the others share the management segment with the edge node.
#
# Translation rather than an advertised route, and the edge address on the
# switch side without its prefix route, for the reason infra/tailscale/acls.json
# gives: at home the management prefix is the house network, which must not
# become a route every device on the tailnet can use, nor one the edge node
# reaches through this port. Nothing here advertises anything.
#
# The switches advertise a TCP MSS for a 1500-byte link, tailscale0 carries
# 1280, and full-size segments coming back from the controller vanish inside
# the tailnet rather than asking for a smaller size. Measured on ber1-mgmt: its
# management connection to the controller received only the last segment of
# every reply, and adoption failed. So the edge node clamps the MSS of the
# connections it forwards to the route's MTU.
#
#   mise run rack:edge-path --interface enp89s0 [--dry-run]
#
# It also runs DHCP for the switches behind the edge node, naming the controller
# (tuist-rack-dhcp.service), which is what makes a factory switch zero touch.
#
# Idempotent. What it installs survives a reboot of the edge node through two
# units, tuist-mgmt-path.service and tuist-rack-dhcp.service. See infra/rack-switch-fleet/AGENTS.md.

set -euo pipefail

FLEET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$FLEET_ROOT/lib/config.sh"

SITE="${RACK_SITE:-ber1}"
interface=""
dry_run=0
while (( $# )); do
  case "$1" in
    --interface) interface="${2:-}"; shift 2;;
    --site) SITE="${2:-}"; shift 2;;
    --dry-run) dry_run=1; shift;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done

site_file="$(fleet_site_file "$SITE")"
[ -f "$site_file" ] || { echo "error: no site definition at $site_file" >&2; exit 2; }
[ -n "$interface" ] || { echo "error: --interface names the edge node's port the switches hang off" >&2; exit 2; }
if ! [[ "$interface" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "error: '$interface' is not an interface name" >&2
  exit 2
fi

edge="$(jq -r '.management.edge.ssh // empty' "$site_file")"
edge_address="$(jq -r '.management.edge.address // empty' "$site_file")"
if [ -z "$edge" ] || [ -z "$edge_address" ]; then
  echo "error: $SITE has no management.edge with ssh and address" >&2
  exit 2
fi
mapfile -t switches < <(jq -r '.devices[] | .mgmt_address' "$site_file")
mapfile -t behind < <(jq -r '.devices[] | select(.behind_edge) | .mgmt_address' "$site_file")
(( ${#switches[@]} )) || { echo "error: $SITE has no devices" >&2; exit 2; }
tag="tag:tuist-rack-edge"
hostname="${edge#*@}"

# accept-new: the edge node is addressed by name, and a first contact by name
# must not fail batch mode on an unknown host key.
on_edge() { ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$edge" "$1"; }
indent() { while IFS= read -r line; do printf '  %s\n' "$line"; done; }

on_edge true 2>/dev/null || { echo "error: cannot reach $edge over SSH" >&2; exit 1; }

# --- refuse to hijack a network the edge node lives on ------------------------

default_interfaces="$(on_edge "ip route show default | awk '{print \$5}'" 2>/dev/null || true)"
if grep -qx -- "$interface" <<<"$default_interfaces"; then
  echo "error: $interface carries $edge's default route; the switches' port is a different one" >&2
  exit 1
fi
on_edge "ip link show dev $interface" >/dev/null 2>&1 || { echo "error: $edge has no interface $interface" >&2; exit 1; }

# --- what the edge node runs at every boot -----------------------------------

# The provisioning segment is where a factory switch gets its first address
# from rack:ztp, with the edge node as its gateway and, once the controller's
# address is known, option 138 naming the controller; so it is translated too.
provisioning="$(jq -r '.management.edge.provisioning // empty' "$site_file")"
sources="$(IFS=,; echo "${switches[*]}")"
if [ -n "$provisioning" ]; then
  provisioning_net="$(fleet_network "$provisioning")"
  sources="$sources,$provisioning_net"
fi
# The edge address carries the management prefix without its route, so the DHCP
# server below sees the management subnet on this port while the edge node
# keeps reaching that subnet through its uplinks.
management_length="$(jq -r '.management.prefix' "$site_file" | cut -d/ -f2)"
controller_address="$(jq -r '.management.controller.address // empty' "$site_file")"
mapfile -t known < <(jq -r '.devices[] | select(.behind_edge and .mac) | "\(.mac) \(.mgmt_address) \(.name)"' "$site_file")
apply_script="#!/bin/sh
# generated by rack:edge-path from infra/rack-switch-fleet/sites/$SITE.json
set -e
ip link set $interface up
ip addr del $edge_address/32 dev $interface 2>/dev/null || true
ip addr replace $edge_address/$management_length dev $interface noprefixroute
${provisioning:+ip addr replace $provisioning dev $interface
}$(for s in "${behind[@]}"; do echo "ip route replace $s/32 dev $interface src $edge_address"; done)
sysctl -qw net.ipv4.ip_forward=1
nft -f - <<'NFT'
table ip tuist_mgmt_path
delete table ip tuist_mgmt_path
table ip tuist_mgmt_path {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname \"tailscale0\" ip saddr { $sources } masquerade
  }
  chain forward {
    type filter hook forward priority mangle;
    oifname \"tailscale0\" ip saddr { $sources } tcp flags & (syn | rst) == syn tcp option maxseg size set rt mtu
  }
}
table netdev tuist_rack_dhcp
delete table netdev tuist_rack_dhcp
table netdev tuist_rack_dhcp {
  chain replies {
    type filter hook egress device \"$interface\" priority 0;
$(for k in "${known[@]}"; do mac="${k%% *}"; echo "    udp sport 67 udp dport 68 @th,288,48 0x${mac//:/} ether daddr set $mac"; done)
  }
}
NFT"

# The switches behind the edge get their first address here, and with it the
# controller's: a factory switch told where its controller is shows up there as
# pending, and the reconciler adopts it. A known switch gets its site address
# and the edge node as its router; anything else gets the provisioning range.
#
# The SG3452's DHCP client (firmware 1.30) sets the broadcast flag and then
# ignores broadcast replies, so the rule above addresses each known switch's
# replies to its MAC, matched on the client hardware address in the reply (36
# bytes into the UDP header).
dhcp_conf="# generated by rack:edge-path from infra/rack-switch-fleet/sites/$SITE.json
port=0
interface=$interface
bind-interfaces
no-hosts
no-resolv
dhcp-authoritative
dhcp-leasefile=/var/lib/misc/tuist-rack-dhcp.leases
log-dhcp
dhcp-range=set:known,$(fleet_network "$edge_address/$management_length" | cut -d/ -f1),static,$(fleet_prefix_mask "$management_length"),infinite
dhcp-option=tag:known,option:router,$edge_address
$(for k in "${known[@]}"; do read -r mac address name <<<"$k"; echo "dhcp-host=$mac,$address,$name,infinite"; done)
${provisioning:+dhcp-range=set:provisioning,${provisioning_net%.*/*}.100,${provisioning_net%.*/*}.150,$(fleet_prefix_mask "${provisioning#*/}"),1h
dhcp-option=tag:provisioning,option:router,${provisioning%/*}
}${controller_address:+dhcp-option=138,$controller_address}"

dhcp_unit="[Unit]
Description=DHCP for the rack switches behind the edge node, naming their controller
Requires=tuist-mgmt-path.service
After=tuist-mgmt-path.service

[Service]
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/tuist-rack-dhcp.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target"

unit="[Unit]
Description=Route the rack switches' management addresses into the tailnet
Wants=network-online.target
After=network-online.target tailscaled.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/tuist-mgmt-path

[Install]
WantedBy=multi-user.target"

echo "edge node     $edge, port $interface, answering the switches at $edge_address"
echo "switches      ${switches[*]}"
echo ""
echo "/usr/local/sbin/tuist-mgmt-path:"
indent <<<"$apply_script"
echo ""
echo "/etc/systemd/system/tuist-mgmt-path.service:"
indent <<<"$unit"
echo ""
echo "/etc/tuist-rack-dhcp.conf:"
indent <<<"$dhcp_conf"
echo ""
echo "/etc/systemd/system/tuist-rack-dhcp.service:"
indent <<<"$dhcp_unit"

if (( dry_run )); then
  echo ""
  echo "dry run, nothing changed on $edge"
  exit 0
fi

# --- install it --------------------------------------------------------------

printf '%s\n' "$apply_script" | on_edge "sudo -n tee /usr/local/sbin/tuist-mgmt-path >/dev/null && sudo -n chmod 755 /usr/local/sbin/tuist-mgmt-path"
printf '%s\n' "$unit" | on_edge "sudo -n tee /etc/systemd/system/tuist-mgmt-path.service >/dev/null"
on_edge "sudo -n systemctl daemon-reload && sudo -n systemctl enable --quiet tuist-mgmt-path.service && sudo -n systemctl restart tuist-mgmt-path.service"
echo ""
echo "installed and started tuist-mgmt-path.service on $edge"

if ! on_edge 'test -x /usr/sbin/dnsmasq' >/dev/null 2>&1; then
  on_edge 'sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dnsmasq-base >/dev/null'
  echo "installed dnsmasq-base on $edge"
fi
printf '%s\n' "$dhcp_conf" | on_edge "sudo -n tee /etc/tuist-rack-dhcp.conf >/dev/null"
printf '%s\n' "$dhcp_unit" | on_edge "sudo -n tee /etc/systemd/system/tuist-rack-dhcp.service >/dev/null"
on_edge "sudo -n systemctl daemon-reload && sudo -n systemctl enable --quiet tuist-rack-dhcp.service && sudo -n systemctl restart tuist-rack-dhcp.service"
echo "installed and started tuist-rack-dhcp.service on $edge"

# Tailscale from its own apt repository, for the release Ubuntu reports.
# shellcheck disable=SC2016  # expanded on the edge node, not here
if ! on_edge 'command -v tailscale' >/dev/null 2>&1; then
  on_edge '. /etc/os-release
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" | sudo -n tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.tailscale-keyring.list" | sudo -n tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    sudo -n apt-get update -qq && sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale >/dev/null'
  echo "installed tailscale on $edge"
fi

if on_edge 'tailscale status --json 2>/dev/null' | jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
  echo "$edge is on the tailnet as $(on_edge 'tailscale ip -4' 2>/dev/null | head -1)"
else
  echo ""
  echo "$edge is not on the tailnet yet. Joining is the one step that needs a person: the"
  echo "ACL in infra/tailscale/acls.json must already carry $tag, and the login URL this"
  echo "prints has to be opened by a tailnet admin:"
  echo "  ssh -t $edge sudo tailscale up --hostname=$hostname --advertise-tags=$tag"
  echo "Then disable key expiry for $hostname in the admin console, since it is a server."
fi
