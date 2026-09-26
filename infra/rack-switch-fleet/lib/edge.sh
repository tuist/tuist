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
# reaches through this port. The only routes the edges advertise are the
# machines' own addresses on the machines segment and the installed power
# devices' management addresses, one /32 each.
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
  fleet_edge_check_vrrp "$site_file" || return 1
  fleet_edge_check_machines "$site_file" || return 1
  fleet_edge_check_power "$site_file"
}

# The power devices the tailnet reaches through the edge, one management
# address per line: each installed power node with a management address whose
# management link is on a switch behind the edge.
fleet_edge_power() {
  local site_file="$1"
  jq -r '
    [.devices[]? | select(.behind_edge) | .name] as $behind |
    .nodes[]? | select(.role == "power" and .status == "installed" and (.mgmt_address // "") != "") |
    select(any(.links[]?; .purpose == "management" and (.switch as $s | $behind | index($s)))) |
    .mgmt_address
  ' "$site_file"
}

fleet_edge_check_power() {
  local site_file="$1" prefix address bad=""
  prefix="$(jq -r '.management.prefix' "$site_file")"
  while read -r address; do
    [ -n "$address" ] || continue
    if ! fleet_is_ipv4 "$address" || ! fleet_in_network "$address" "$prefix"; then
      bad="${bad:+$bad$'\n'}power device address $address is not in the management prefix $prefix"
    fi
  done < <(fleet_edge_power "$site_file")
  if [ -n "$bad" ]; then
    echo "error: the power devices behind the edge are wrong:" >&2
    printf '  %s\n' "$bad" >&2
    return 1
  fi
}

fleet_is_ipv4() { [[ "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] && (( BASH_REMATCH[1] < 256 && BASH_REMATCH[2] < 256 && BASH_REMATCH[3] < 256 && BASH_REMATCH[4] < 256 )); }

# Whether an address is inside a prefix: 10.10.0.101 is in 10.10.0.1/24.
fleet_in_network() { [ "$(fleet_network "$1/${2#*/}")" = "$(fleet_network "$2")" ]; }

# The machines on the site's machines segment, one per line: node, the MAC of
# its data link, and its address, which is its RackHost's. A machine is a node
# whose role is on the segment; one still planned is left out until it is
# racked.
fleet_edge_machines() {
  local site_file="$1" values="${2:-$FLEET_RACK_VALUES}" hosts
  hosts="$(yq -o=json '[.rackFleet.hosts[]? | {"key": .name, "value": (.address // "")}] | from_entries' "$values" 2>/dev/null)" || hosts=''
  [ -n "$hosts" ] || hosts='{}'
  jq -r --argjson hosts "$hosts" '
    ([(.node_roles // {}) | to_entries[] | select(.value.segment == "machines") | .key]) as $roles |
    .nodes[]? | select((.role as $r | $roles | index($r)) and .status != "planned") |
    [.name, ([.links[] | select(.purpose == "data") | .mac // empty] | first // ""),
     ($hosts[.rack_host // ""] // "")] | join("\t")
  ' "$site_file"
}

# The segment the site's runners sit on, behind the edges. Each edge has an
# address of its own on it, and the master also holds the gateway. Every
# machine on it has a RackHost, a MAC to reserve its address against, and an
# address inside the segment that no edge uses.
fleet_edge_check_machines() {
  local site_file="$1" values="${2:-$FLEET_RACK_VALUES}" gateway bad="" node address mac
  [ -n "$(jq -r '.management.edge.machines.vlan // empty' "$site_file")" ] || return 0
  gateway="$(jq -r '.management.edge.machines.gateway // empty' "$site_file")"
  if ! [[ "$gateway" =~ ^[0-9.]+/([0-9]|[12][0-9]|3[0-2])$ ]] || ! fleet_is_ipv4 "${gateway%/*}"; then
    echo "error: management.edge.machines.gateway '$gateway' is not an address with its prefix length" >&2
    return 1
  fi
  local -a used=("${gateway%/*}")
  bad="$(jq -r '
    ([.nodes[]? | select(.role == "edge") | .name] | sort) as $edges |
    ([.management.edge.machines.members[]?.node] | sort) as $members |
    (if $members != $edges
     then "management.edge.machines.members are \($members | join(", ")), but the site'"'"'s edges are \($edges | join(", "))" else empty end),
    (.nodes[]? | select(.rack_host == null and (.role as $r | $roles | index($r))) |
      "\(.name) is on the machines segment and names no RackHost")
  ' --argjson roles "$(jq '[(.node_roles // {}) | to_entries[] | select(.value.segment == "machines") | .key]' "$site_file")" "$site_file")"
  while IFS=$'\t' read -r node address; do
    [ -n "$node" ] || continue
    if ! fleet_is_ipv4 "$address" || ! fleet_in_network "$address" "$gateway"; then
      bad="${bad:+$bad$'\n'}$node's machines address $address is not in $gateway"
    elif [[ " ${used[*]} " == *" $address "* ]]; then
      bad="${bad:+$bad$'\n'}$node's machines address $address is already the gateway's or another edge's"
    fi
    used+=("$address")
  done < <(jq -r '.management.edge.machines.members[]? | "\(.node)\t\(.address)"' "$site_file")
  for address in $(jq -r '.management.edge.machines.dns[]?' "$site_file"); do
    fleet_is_ipv4 "$address" || bad="${bad:+$bad$'\n'}machines DNS server $address is not an address"
  done
  local -a macs=()
  while IFS=$'\t' read -r node mac address; do
    [ -n "$node" ] || continue
    if ! [[ "$mac" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
      bad="${bad:+$bad$'\n'}$node has no MAC on its data link, in lower case, to reserve its address against"
    fi
    if [ -z "$address" ]; then
      bad="${bad:+$bad$'\n'}$node's RackHost has no address in $(basename "$values")"
    elif ! fleet_is_ipv4 "$address" || ! fleet_in_network "$address" "$gateway"; then
      bad="${bad:+$bad$'\n'}$node's address $address is not in the machines segment $gateway"
    elif [[ " ${used[*]} " == *" $address "* ]]; then
      bad="${bad:+$bad$'\n'}$node's address $address is already the gateway's, an edge's or another machine's"
    fi
    [[ " ${macs[*]} " == *" $mac "* ]] && bad="${bad:+$bad$'\n'}$node shares its MAC with another machine"
    used+=("$address")
    macs+=("$mac")
  done < <(fleet_edge_machines "$site_file" "$values")
  if [ -n "$bad" ]; then
    echo "error: the machines segment is wrong:" >&2
    printf '  %s\n' "$bad" >&2
    return 1
  fi
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
      .vlan as $v | if ($edge_vlans | index($v)) == null then "VLAN \($v) floats an edge address but is not carried_by the edges" else empty end),
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
  local node address uplink_names vrrp_length machines_vlan machines_gateway machines wan_vlan
  vrrp_length="$(jq -r '.management.edge.vrrp.prefix' "$site_file" | cut -d/ -f2)"
  machines_vlan="$(jq -r '.management.edge.machines.vlan // empty' "$site_file")"
  machines_gateway="$(jq -r '.management.edge.machines.gateway // empty' "$site_file")"
  wan_vlan="$(jq -r '.management.edge.wan.vlan // empty' "$site_file")"
  cat <<'SCRIPT'
case "${NODE_NAME:?the pod passes the name of the node it runs on}" in
SCRIPT
  while IFS=$'\t' read -r node address _ uplink_names; do
    machines=""
    if [ -n "$machines_vlan" ]; then
      machines=" machines_address=$(jq -r --arg n "$node" '.management.edge.machines.members[] | select(.node == $n) | .address' "$site_file")/${machines_gateway#*/}"
    fi
    printf '  %s) vrrp_address=%s%s uplinks="%s" ;;\n' "$node" "$address/$vrrp_length" "$machines" "$uplink_names"
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
  # An edge's own address on the machines segment is the source of every
  # tailnet connection it routes to a machine: it is the first address there
  # whose prefix holds the machine's, so either edge can route to the machines
  # whichever of them is master. The gateway beside it is keepalived's, a /32,
  # so giving the gateway up never takes this address with it.
  if [ -n "$machines_vlan" ]; then
    echo "edge_vlan_bond machines0 $machines_vlan"
    # shellcheck disable=SC2016  # expanded by the rendered script, per edge
    echo 'ip addr replace "$machines_address" dev machines0'
  fi
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
  # The machines reach the internet through their gateway, translated onto the
  # uplinks the same way.
  if [ -n "$machines_vlan" ]; then
    [ -n "$uplinks" ] && uplinks+=$'\n'
    uplinks+="    oifname != { \"tailscale0\", \"machines0\", \"$interface\" } ip saddr $(fleet_network "$machines_gateway") masquerade"
  fi
  # The tailnet reaches the power devices through the master's switch port,
  # translated to the edge address there: their gateway is not an edge, so a
  # reply to a tailnet address would not come back. Their replies into the
  # tailnet are clamped like the switches'.
  local power_nat="" power_clamp="" power
  power="$(fleet_edge_power "$site_file" | paste -sd, -)"
  if [ -n "$power" ]; then
    power_nat="    iifname \"tailscale0\" oifname \"$interface\" ip daddr { $power } masquerade"
    power_clamp="    oifname \"tailscale0\" ip saddr { $power } tcp flags & (syn | rst) == syn tcp option maxseg size set rt mtu"
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
${power_nat:+$power_nat
}${uplinks:+$uplinks
}  }
  chain forward {
    type filter hook forward priority mangle;
    oifname "tailscale0" ip saddr { $sources } tcp flags & (syn | rst) == syn tcp option maxseg size set rt mtu
${power_clamp:+$power_clamp
}  }
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
SCRIPT
  [ -n "$machines_vlan" ] && fleet_edge_machines_filter "$site_file"
  echo NFT
}

# What a machine may reach through an edge: the internet, and its own replies.
# A runner executes customer build code, so the management segment, the
# provisioning range, the edges' VRRP link, the switches' port and the tailnet
# are all closed to it, and of the edge itself only DHCP and ping are open. A
# machine on the tailnet reaches it through its own client, not through an
# edge.
fleet_edge_machines_filter() {
  local site_file="$1" interface closed
  interface="$(jq -r '.management.edge.interface' "$site_file")"
  # Each as its network: nft refuses a prefix with host bits set.
  closed="$(jq -r '.management.prefix, (.management.edge.provisioning // empty), .management.edge.vrrp.prefix' "$site_file" |
    while read -r prefix; do fleet_network "$prefix"; done | paste -sd, - | sed 's/,/, /g')"
  cat <<SCRIPT
table inet tuist_rack_machines
delete table inet tuist_rack_machines
table inet tuist_rack_machines {
  chain forward {
    type filter hook forward priority filter;
    iifname "machines0" ct state established,related accept
    iifname "machines0" oifname { "tailscale0", "vrrp0", "$interface" } drop
    iifname "machines0" ip daddr { $closed } drop
  }
  chain input {
    type filter hook input priority filter;
    iifname "machines0" ct state established,related accept
    iifname "machines0" udp dport 67 accept
    iifname "machines0" icmp type echo-request accept
    iifname "machines0" drop
  }
}
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
    # the rack's boot server on the provisioning address, through the shim of
    # iPXE's Secure Boot build, and iPXE, which says so in its user class, the
    # script that asks the server for the host's install; a host with none
    # published gets nothing. The offers carry no vendor class: with PXEClient
    # in it the firmware asks a PXE boot server on port 4011 for the file
    # instead of reading the one the offer names. The file name stays in the
    # packet's file field, not only in option 67, which the firmware asks for:
    # the shim reads the field to find the iPXE named after it.
    echo "dhcp-match=set:netboot,option:client-arch,7"
    echo "dhcp-match=set:netboot,option:client-arch,9"
    echo "dhcp-userclass=set:ipxe,iPXE"
    echo "dhcp-no-override"
    echo "dhcp-boot=tag:netboot,tag:!ipxe,snponly-shim.efi,,${provisioning%/*}"
    echo "dhcp-boot=tag:ipxe,boot.ipxe,,${provisioning%/*}"
  fi
  return 0
}

# DHCP for the machines segment, a dnsmasq of its own beside the switches' one:
# each machine gets its RackHost's address against the MAC of its link, the
# floating gateway as its router, and public resolvers. Both edges answer, since
# each holds an address of its own on the segment, and with reservations and no
# pool the two answers are the same answer. So neither may be authoritative: an
# authoritative server NAKs a request the machine addressed to the other edge
# ("wrong server-ID", measured on ber1-proto-01's first lease), and whichever
# reply lands first decides whether the machine keeps its address or starts
# over. dhcp-authoritative is global, hence a second process, which can share
# port 67 with the first because each serves one interface. A site without the
# segment renders a dnsmasq that serves nothing.
fleet_edge_machines_dhcp() {
  local site_file="$1" gateway dns node mac address
  fleet_edge_check "$site_file" || return 1
  cat <<CONF
# generated by rack:fleet render from infra/rack-switch-fleet/sites/$(basename "$site_file")
port=0
no-hosts
no-resolv
log-facility=-
log-dhcp
CONF
  [ -n "$(jq -r '.management.edge.machines.vlan // empty' "$site_file")" ] || return 0
  gateway="$(jq -r '.management.edge.machines.gateway' "$site_file")"
  cat <<CONF
interface=machines0
bind-dynamic
dhcp-leasefile=/var/lib/misc/tuist-rack-machines.leases
dhcp-range=set:machines,$(fleet_network "$gateway" | cut -d/ -f1),static,$(fleet_prefix_mask "${gateway#*/}"),infinite
dhcp-option=tag:machines,option:router,${gateway%/*}
CONF
  dns="$(jq -r '[.management.edge.machines.dns[]?] | join(",")' "$site_file")"
  [ -n "$dns" ] && echo "dhcp-option=tag:machines,option:dns-server,$dns"
  while IFS=$'\t' read -r node mac address; do
    [ -n "$node" ] && echo "dhcp-host=$mac,$address,$node,infinite"
  done < <(fleet_edge_machines "$site_file")
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
  [ -n "$machines_gateway" ] && printf '    %s/32 dev machines0\n' "${machines_gateway%/*}"
  [ -n "$wan_address" ] && printf '    %s dev wan0\n' "$wan_address"
  printf '  }\n'
  local -a behind
  mapfile -t behind < <(jq -r '.devices[] | select(.behind_edge) | .mgmt_address' "$site_file"; fleet_edge_power "$site_file")
  if [ "${#behind[@]}" -gt 0 ]; then
    printf '  virtual_routes {\n'
    local s
    for s in "${behind[@]}"; do printf '    %s/32 dev %s src %s\n' "$s" "$interface" "$edge_address"; done
    printf '  }\n'
  fi
  printf '}\n'
}

# The tailnet routes the edges advertise, through the node's own tailscaled.
# Both edges advertise the machines' addresses, so the tailnet fails over
# between the edges the way the gateway does. A /32 per machine rather than
# the segment's prefix, so the tailnet reaches the machines the site has and
# nothing else on the segment: not the edges' own addresses, not one nothing is
# reserved at. Each power device behind the edge is a /32 too, advertised only
# by the edge holding the edge address on the switch port, the one edge with a
# route to it, so after a failover its route moves on the script's next run. A
# site with no machines and no power devices advertises nothing, which also
# withdraws what an edge advertised before.
fleet_edge_routes() {
  local site_file="$1" routes="" power interface edge_address
  fleet_edge_check "$site_file" || return 1
  if [ -n "$(jq -r '.management.edge.machines.vlan // empty' "$site_file")" ]; then
    routes="$(fleet_edge_machines "$site_file" | awk -F'\t' '$3 != "" {print $3 "/32"}' | paste -sd, -)"
  fi
  power="$(fleet_edge_power "$site_file" | awk '{print $1 "/32"}' | paste -sd, -)"
  interface="$(jq -r '.management.edge.interface' "$site_file")"
  edge_address="$(jq -r '.management.edge.address' "$site_file")"
  cat <<SCRIPT
#!/bin/sh
# generated by rack:fleet render from infra/rack-switch-fleet/sites/$(basename "$site_file")
routes=$routes
SCRIPT
  if [ -n "$power" ]; then
    cat <<SCRIPT
if ip -4 -o addr show dev $interface 2>/dev/null | grep -qF ' $edge_address/'; then
  routes="\${routes:+\$routes,}$power"
fi
SCRIPT
  fi
  cat <<'SCRIPT'
exec tailscale --socket=/run/tailscale/tailscaled.sock set --advertise-routes="$routes"
SCRIPT
}
