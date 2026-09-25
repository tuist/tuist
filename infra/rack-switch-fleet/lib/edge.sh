# shellcheck shell=bash
# What the rack's edge node runs for the switches, rendered from the site
# definition into infra/helm/rack-edge/sites/<site>/, where the rack-edge
# DaemonSet picks it up on the site's edge node.
#
# The switches reach the Omada controller, which lives in a cluster on the
# tailnet, by a static route to the tailnet's range via the edge node's address;
# the edge node forwards that traffic into tailscale0, translated to its own
# tailnet address. A switch marked `behind_edge` hangs off the edge node's
# switch port, so it also gets a host route there; the others share the
# management segment with the edge node.
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
# Sourced by fleet.sh and by the bats tests. Pure text, like lib/config.sh.

FLEET_EDGE_CHART="${FLEET_EDGE_CHART:-$FLEET_ROOT/../helm/rack-edge}"

# The site's rendered files, or nothing when its edge node names no switch port.
fleet_edge_dir() {
  local site_file="$1"
  [ -n "$(jq -r '.management.edge.interface // empty' "$site_file")" ] || return 0
  echo "$FLEET_EDGE_CHART/sites/$(basename "$site_file" .json)"
}

fleet_edge_check() {
  local site_file="$1" interface
  interface="$(jq -r '.management.edge.interface // empty' "$site_file")"
  if ! [[ "$interface" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: management.edge.interface '$interface' is not an interface name" >&2
    return 1
  fi
  if [ -z "$(jq -r '.management.edge.address // empty' "$site_file")" ]; then
    echo "error: management.edge has an interface but no address" >&2
    return 1
  fi
  if [ "$(jq -r '.management.edge.netboot // false' "$site_file")" = true ] && [ -z "$(jq -r '.management.edge.provisioning // empty' "$site_file")" ]; then
    echo "error: management.edge.netboot serves the provisioning range, and the site has none" >&2
    return 1
  fi
  fleet_edge_check_vrrp "$site_file"
}

# The edges share the site's floating addresses through keepalived, which
# talks to its peers on a VLAN of its own. Every edge node is a member, each
# with an address in the VRRP prefix and at least one data link to carry it; a
# VLAN the floating networks name has to be one the switches carry to the
# edges.
fleet_edge_check_vrrp() {
  local site_file="$1" bad prefix
  prefix="$(jq -r '.management.edge.vrrp.prefix // empty' "$site_file")"
  if [ -z "$prefix" ] || [ -z "$(jq -r '.management.edge.vrrp.vlan // empty' "$site_file")" ]; then
    echo "error: management.edge.vrrp needs a vlan and a prefix: the edges share their addresses through it" >&2
    return 1
  fi
  bad="$(jq -r --slurpfile hardware "$FLEET_NODE_MODELS" '
    $hardware[0] as $hw |
    .management.edge as $e |
    ([.vlans[]? | select(.carried_by == "edges") | .id]) as $edge_vlans |
    ([.nodes[]? | select(.role == "edge") | .name] | sort) as $edges |
    ([$e.vrrp.members[]?.node] | sort) as $members |
    (.vlans[]? | select(.carried_by != null and .carried_by != "edges") |
      "VLAN \(.id) is carried_by \(.carried_by), which is not a thing the switches know"),
    (if ($edge_vlans | index($e.vrrp.vlan)) == null
     then "management.edge.vrrp.vlan \($e.vrrp.vlan) is not a VLAN carried_by the edges" else empty end),
    (if $members != $edges
     then "management.edge.vrrp.members are \($members | join(", ")), but the site'"'"'s edges are \($edges | join(", "))" else empty end),
    (if ($members | unique | length) != ($members | length) then "an edge is a VRRP member twice" else empty end),
    (if ([$e.vrrp.members[]?.address] | unique | length) != ([$e.vrrp.members[]?.address] | length)
     then "two edges share a VRRP address" else empty end),
    ($e.vrrp.members[]? as $m | .nodes[]? | select(.name == $m.node) | . as $n |
      if ([.links[] | select(.purpose == "data")] | length) == 0 then "\(.name) has no data link to carry VRRP"
      elif ([.links[] | select(.purpose == "data") | $hw[$n.hardware // ""].interfaces[.nic].os_name // empty] | length) == 0
      then "\(.name): its hardware names no interface for its data links" else empty end),
    (($e.machines // {}), ($e.wan // {}) | select(.vlan != null) |
      if ($edge_vlans | index(.vlan)) == null then "VLAN \(.vlan) floats an edge address but is not carried_by the edges" else empty end),
    (if ($e.machines.gateway // null) != null and ($e.machines.vlan // null) == null
     then "management.edge.machines has a gateway but no vlan" else empty end),
    (if ($e.wan.address // null) != null and ($e.wan.vlan // null) == null
     then "management.edge.wan has an address but no vlan" else empty end)
  ' "$site_file")"
  local node address
  while IFS=$'\t' read -r node address; do
    [ -n "$node" ] || continue
    if ! [[ "$node" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      bad="${bad:+$bad$'\n'}VRRP member '$node' is not a node name"
      continue
    fi
    if ! [[ "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ "$(fleet_network "$address/${prefix#*/}")" != "$(fleet_network "$prefix")" ]; then
      bad="${bad:+$bad$'\n'}$node's VRRP address $address is not in $prefix"
    fi
  done < <(jq -r '.management.edge.vrrp.members[]? | "\(.node)\t\(.address)"' "$site_file")
  if [ -n "$bad" ]; then
    echo "error: the edges' shared addresses are wrong:" >&2
    printf '  %s\n' "$bad" >&2
    return 1
  fi
}

# The site's edges in order of preference, one per line: node, VRRP address,
# priority, and the OS names of the interfaces its data links leave from.
fleet_edge_members() {
  local site_file="$1"
  jq -r --slurpfile hardware "$FLEET_NODE_MODELS" '
    $hardware[0] as $hw |
    . as $site |
    .management.edge.vrrp.members | to_entries[] |
    .key as $i | .value as $m |
    ($site.nodes[] | select(.name == $m.node)) as $n |
    [$m.node, $m.address, (150 - 50 * $i | tostring),
     ([$n.links[] | select(.purpose == "data") | $hw[$n.hardware].interfaces[.nic].os_name] | join(" "))] | join("\t")
  ' "$site_file"
}

# The management path, as a POSIX sh script run at pod start and again every
# few minutes. Idempotent: each nft table is replaced whole in one transaction,
# so re-running it keeps the connections it translated.
fleet_edge_path() {
  local site_file="$1" interface edge_address length provisioning sources netboot
  local -a switches known
  fleet_edge_check "$site_file" || return 1
  interface="$(jq -r '.management.edge.interface' "$site_file")"
  edge_address="$(jq -r '.management.edge.address' "$site_file")"
  length="$(jq -r '.management.prefix' "$site_file" | cut -d/ -f2)"
  provisioning="$(jq -r '.management.edge.provisioning // empty' "$site_file")"
  netboot="$(jq -r '.management.edge.netboot // false' "$site_file")"
  mapfile -t switches < <(jq -r '.devices[] | .mgmt_address' "$site_file")
  mapfile -t known < <(jq -r '.devices[] | select(.behind_edge and .mac) | .mac' "$site_file")
  # The provisioning segment is where a factory switch gets its first address,
  # with the edge node as its gateway, so it is translated too.
  sources="$(IFS=,; echo "${switches[*]}")${provisioning:+,$(fleet_network "$provisioning")}"

  cat <<SCRIPT
#!/bin/sh
# generated by rack:fleet render from infra/rack-switch-fleet/sites/$(basename "$site_file")
set -e
if ip route show default | awk '{for (i = 1; i < NF; i++) if (\$i == "dev") print \$(i + 1)}' | grep -qx '$interface'; then
  echo "$interface carries this node's default route; the switches' port is a different one" >&2
  exit 1
fi
if [ "\$(cat /proc/sys/net/ipv4/ip_forward)" != 1 ]; then
  echo "net.ipv4.ip_forward is off; the node's converge turns it on" >&2
  exit 1
fi
ip link set $interface up
SCRIPT
  # This node's own end of VRRP. Each edge VLAN rides an active-backup bond
  # over one VLAN interface per uplink, so it survives losing either ToR, and
  # the edges never both believe the other is gone while both are up.
  local node address uplink_names vrrp_length machines_vlan wan_vlan
  vrrp_length="$(jq -r '.management.edge.vrrp.prefix' "$site_file" | cut -d/ -f2)"
  machines_vlan="$(jq -r '.management.edge.machines.vlan // empty' "$site_file")"
  wan_vlan="$(jq -r '.management.edge.wan.vlan // empty' "$site_file")"
  cat <<'SCRIPT'
case "${NODE_NAME:?the pod passes the name of the node it runs on}" in
SCRIPT
  while IFS=$'\t' read -r node address _ uplink_names; do
    printf '  %s) vrrp_address=%s uplinks="%s" ;;\n' "$node" "$address/$vrrp_length" "$uplink_names"
  done < <(fleet_edge_members "$site_file")
  cat <<'SCRIPT'
  *) echo "$NODE_NAME is not one of the site's edges" >&2; exit 1 ;;
esac
edge_vlan_bond() {
  bond=$1 vlan=$2 i=0
  ip link show "$bond" >/dev/null 2>&1 || ip link add "$bond" type bond mode active-backup miimon 100
  for uplink in $uplinks; do
    i=$((i + 1))
    member="$bond-$i"
    ip link show "$member" >/dev/null 2>&1 || ip link add link "$uplink" name "$member" type vlan id "$vlan"
    if [ ! -e "/sys/class/net/$member/master" ]; then
      ip link set "$member" down
      ip link set "$member" master "$bond"
    fi
  done
  ip link set "$bond" up
}
SCRIPT
  echo "edge_vlan_bond vrrp0 $(jq -r '.management.edge.vrrp.vlan' "$site_file")"
  cat <<'SCRIPT'
ip addr replace "$vrrp_address" dev vrrp0
SCRIPT
  [ -n "$machines_vlan" ] && echo "edge_vlan_bond machines0 $machines_vlan"
  [ -n "$wan_vlan" ] && echo "edge_vlan_bond wan0 $wan_vlan"
  # The floating addresses, and the routes that use them as their source, are
  # keepalived's, on whichever edge holds them. On the switch port they are
  # the only addresses: a port the site moved away from gives them up, or its
  # connected route, kept while the cable is gone, would still claim the
  # provisioning range.
  local owned="\$4 == \"$edge_address/$length\""
  [ -n "$provisioning" ] && owned="$owned || \$4 == \"$provisioning\""
  cat <<SCRIPT
ip -o -4 addr show | awk -v port='$interface' '\$2 != port && ($owned) {print \$2, \$4}' |
  while read -r dev address; do ip addr del "\$address" dev "\$dev"; done
SCRIPT
  # A netbooting installer can take its default route from either of its DHCP
  # leases, the provisioning one through this node or its uplinks' one, so
  # the provisioning range is translated onto the uplinks too.
  local uplinks=""
  if [ "$netboot" = true ]; then
    uplinks="    oifname != { \"tailscale0\", \"$interface\" } ip saddr $(fleet_network "$provisioning") masquerade"
  fi
  # The SG3452's DHCP client (firmware 1.30) sets the broadcast flag and then
  # ignores broadcast replies, so the netdev table addresses each known
  # switch's replies to its MAC, matched on the client hardware address in the
  # reply (36 bytes into the UDP header).
  cat <<SCRIPT
nft -f - <<'NFT'
table ip tuist_mgmt_path
delete table ip tuist_mgmt_path
table ip tuist_mgmt_path {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "tailscale0" ip saddr { $sources } masquerade
${uplinks:+$uplinks
}  }
  chain forward {
    type filter hook forward priority mangle;
    oifname "tailscale0" ip saddr { $sources } tcp flags & (syn | rst) == syn tcp option maxseg size set rt mtu
  }
}
table netdev tuist_rack_dhcp
delete table netdev tuist_rack_dhcp
table netdev tuist_rack_dhcp {
  chain replies {
    type filter hook egress device "$interface" priority 0;
SCRIPT
  local mac
  for mac in "${known[@]}"; do echo "    udp sport 67 udp dport 68 @th,288,48 0x${mac//:/} ether daddr set $mac"; done
  cat <<'SCRIPT'
  }
}
NFT
SCRIPT
}

# DHCP for the switches behind the edge node, naming the controller in option
# 138: a factory switch told where its controller is shows up there as pending,
# and the rack switch controller adopts it. A known switch gets its site address
# and the edge node as its router; anything else gets the provisioning range.
# The edge address carries the management prefix without its route, so dnsmasq
# sees the management subnet on this port while the node keeps reaching that
# subnet through its uplinks. bind-dynamic rather than bind-interfaces: the
# standby edge holds none of the port's addresses, and with bind-interfaces
# dnsmasq exits with "unknown interface" there (measured on ber1-edge-b).
fleet_edge_dhcp() {
  local site_file="$1" interface edge_address length provisioning provisioning_net controller domain
  local -a known
  fleet_edge_check "$site_file" || return 1
  interface="$(jq -r '.management.edge.interface' "$site_file")"
  edge_address="$(jq -r '.management.edge.address' "$site_file")"
  length="$(jq -r '.management.prefix' "$site_file" | cut -d/ -f2)"
  provisioning="$(jq -r '.management.edge.provisioning // empty' "$site_file")"
  controller="$(jq -r '.management.controller.address // empty' "$site_file")"
  domain="$(jq -r '.management.edge.domain // empty' "$site_file")"
  if [ -n "$domain" ] && ! [[ "$domain" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
    echo "error: management.edge.domain '$domain' is not a domain name" >&2
    return 1
  fi
  mapfile -t known < <(jq -r '.devices[] | select(.behind_edge and .mac) | "\(.mac),\(.mgmt_address),\(.name)"' "$site_file")

  cat <<CONF
# generated by rack:fleet render from infra/rack-switch-fleet/sites/$(basename "$site_file")
port=0
interface=$interface
bind-dynamic
no-hosts
no-resolv
dhcp-authoritative
dhcp-leasefile=/var/lib/misc/tuist-rack-dhcp.leases
log-facility=-
log-dhcp
dhcp-range=set:known,$(fleet_network "$edge_address/$length" | cut -d/ -f1),static,$(fleet_prefix_mask "$length"),infinite
dhcp-option=tag:known,option:router,$edge_address
CONF
  local k
  for k in "${known[@]}"; do echo "dhcp-host=$k,infinite"; done
  if [ -n "$provisioning" ]; then
    provisioning_net="$(fleet_network "$provisioning")"
    echo "dhcp-range=set:provisioning,${provisioning_net%.*/*}.100,${provisioning_net%.*/*}.150,$(fleet_prefix_mask "${provisioning#*/}"),1h"
    echo "dhcp-option=tag:provisioning,option:router,${provisioning%/*}"
  fi
  [ -n "$controller" ] && echo "dhcp-option=138,$controller"
  # Option 15 for every machine on the segment: AMT activates in admin control
  # mode only when it is a suffix of its provisioning certificate's name.
  [ -n "$domain" ] && echo "dhcp-option=option:domain-name,$domain"
  if [ "$(jq -r '.management.edge.netboot // false' "$site_file")" = true ]; then
    # x86-64 UEFI firmware (client architectures 7 and 9) netboots iPXE from
    # the rack's boot server on the provisioning address, and iPXE, which says
    # so in its user class, the script that asks the server for the host's
    # install; a host with none published gets nothing. The offers carry no
    # vendor class: with PXEClient in it the firmware asks a PXE boot server
    # on port 4011 for the file instead of reading the one the offer names.
    echo "dhcp-match=set:netboot,option:client-arch,7"
    echo "dhcp-match=set:netboot,option:client-arch,9"
    echo "dhcp-userclass=set:ipxe,iPXE"
    echo "dhcp-boot=tag:netboot,tag:!ipxe,snponly.efi,,${provisioning%/*}"
    echo "dhcp-boot=tag:ipxe,boot.ipxe,,${provisioning%/*}"
  fi
  return 0
}

# keepalived's configuration for one edge node. The edges run one VRRP
# instance, unicast between their addresses on the VRRP bond, and whichever is
# master holds every floating address: the switches' gateway and the
# provisioning address on the switch port, and the machines' gateway and the
# WAN address once the site has them. The standby holds none, so it has no WAN
# address until it takes over. The first member is preferred and takes the
# addresses back a minute after it returns. An edge whose switch port has no
# link never becomes master. An advert counts only when it comes from the other
# edge's address and carries the site's password, which the rack-edge chart
# generates and mounts; only the edges are on the VRRP VLAN, so a device that
# could reach an edge's address cannot read it.
fleet_edge_keepalived() {
  local site_file="$1" node="$2" interface edge_address length provisioning machines_gateway wan_address
  local self address priority peers=() member member_address
  fleet_edge_check "$site_file" || return 1
  self="$(fleet_edge_members "$site_file" | awk -F'\t' -v n="$node" '$1 == n')"
  if [ -z "$self" ]; then
    echo "error: $node is not one of $(basename "$site_file")'s edges" >&2
    return 1
  fi
  IFS=$'\t' read -r _ address priority _ <<<"$self"
  while IFS=$'\t' read -r member member_address _; do
    [ "$member" = "$node" ] || peers+=("$member_address")
  done < <(fleet_edge_members "$site_file")
  interface="$(jq -r '.management.edge.interface' "$site_file")"
  edge_address="$(jq -r '.management.edge.address' "$site_file")"
  length="$(jq -r '.management.prefix' "$site_file" | cut -d/ -f2)"
  provisioning="$(jq -r '.management.edge.provisioning // empty' "$site_file")"
  machines_gateway="$(jq -r '.management.edge.machines.gateway // empty' "$site_file")"
  wan_address="$(jq -r '.management.edge.wan.address // empty' "$site_file")"

  cat <<CONF
# generated by rack:fleet render from infra/rack-switch-fleet/sites/$(basename "$site_file")
global_defs {
  router_id $node
  vrrp_garp_master_refresh 60
  vrrp_check_unicast_src
}

vrrp_instance $(basename "$site_file" .json)_edge {
  state BACKUP
  interface vrrp0
  virtual_router_id 1
  priority $priority
  preempt_delay 60
  advert_int 1
  unicast_src_ip $address
  include /etc/rack-edge-vrrp/authentication.conf
CONF
  if [ "${#peers[@]}" -gt 0 ]; then
    printf '  unicast_peer {\n'
    printf '    %s\n' "${peers[@]}"
    printf '  }\n'
  fi
  cat <<CONF
  track_interface {
    $interface
  }
  virtual_ipaddress {
    $edge_address/$length dev $interface noprefixroute
CONF
  [ -n "$provisioning" ] && printf '    %s dev %s\n' "$provisioning" "$interface"
  [ -n "$machines_gateway" ] && printf '    %s dev machines0\n' "$machines_gateway"
  [ -n "$wan_address" ] && printf '    %s dev wan0\n' "$wan_address"
  printf '  }\n'
  local -a behind
  mapfile -t behind < <(jq -r '.devices[] | select(.behind_edge) | .mgmt_address' "$site_file")
  if [ "${#behind[@]}" -gt 0 ]; then
    printf '  virtual_routes {\n'
    local s
    for s in "${behind[@]}"; do printf '    %s/32 dev %s src %s\n' "$s" "$interface" "$edge_address"; done
    printf '  }\n'
  fi
  printf '}\n'
}
