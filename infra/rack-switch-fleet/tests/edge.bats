#!/usr/bin/env bats
# The edge nodes: the management path to the tailnet, the files the rack-edge
# chart runs, and the machines segment.

load helpers

# --- the path from switches behind the edge node to the tailnet --------------

@test "an interface address gives the network it sits in" {
    run fleet_sh "fleet_network 192.168.50.1/24; fleet_network 10.1.2.3/16"
    [ "${lines[0]}" = "192.168.50.0/24" ]
    [ "${lines[1]}" = "10.1.0.0/16" ]
}

@test "a prefix length becomes the mask the switch CLI takes" {
    run fleet_sh "for b in 0 10 24 32; do fleet_prefix_mask \$b; done"
    [ "${lines[0]}" = "0.0.0.0" ]
    [ "${lines[1]}" = "255.192.0.0" ]
    [ "${lines[2]}" = "255.255.255.0" ]
    [ "${lines[3]}" = "255.255.255.255" ]
}

# The site with a VLAN, a lag on tor-b in place of the ISL lag, and two ports
# with settings of their own, for the render features the rack does not use yet.
# Their forms were read off ber1-tor-b after the controller wrote each one.
site_with_vlans_and_lag() {
    jq '.vlans = [{id: 20, name: "storage"}]
        | del(.devices[].lags)
        | (.devices[] | select(.name == "ber1-tor-b")) |= (
            .lags = [{id: 1, name: "uplink", ports: [29, 30]}]
            | .ports["29"] = {purpose: "data", peer: "uplink-peer", media: "dac"}
            | .ports["30"] = {purpose: "data", peer: "uplink-peer", media: "dac"}
            | .ports["11"] = {purpose: "data", peer: "none", media: "dac", vlans: []}
            | .ports["12"] = {purpose: "data", peer: "none", media: "dac", spanning_tree: false, description: "no stp here"})' \
        "$SITE_FILE" > "$BATS_TEST_TMPDIR/site-vlans.json"
    echo "$BATS_TEST_TMPDIR/site-vlans.json"
}

@test "a site VLAN is carried tagged on every port that names none, as the controller does" {
    site="$(site_with_vlans_and_lag)"
    run fleet_render "$site" ber1-tor-b
    [ "$status" -eq 0 ]
    [[ "$output" == *$'vlan 20\n name "storage"'* ]]
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render '$site' ber1-tor-b | fleet_context | grep -c \$'\\tswitchport general allowed vlan 20 tagged\$'"
    # 32 ports less port 11, which names no VLANs, and ports 2 to 10, whose runners are on
    # the machines segment, plus the lag's own interface
    [ "$output" = "23" ]
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render '$site' ber1-tor-b | fleet_context | grep -c '^interface ten-gigabitEthernet 1/0/11	switchport'"
    [ "$output" = "0" ]
}

@test "a lag renders as a port-channel and its members take its name" {
    site="$(site_with_vlans_and_lag)"
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render '$site' ber1-tor-b | fleet_context"
    [[ "$output" == *$'interface port-channel 1\tdescription "uplink"'* ]]
    [[ "$output" == *$'interface ten-gigabitEthernet 1/0/29\tchannel-group 1 mode active'* ]]
    [[ "$output" == *$'interface ten-gigabitEthernet 1/0/30\tdescription "uplink"'* ]]
}

# The lag fixture with one more edit applied to ber1-tor-b, for the lag guards.
site_with_lag_edit() {
    jq "(.devices[] | select(.name == \"ber1-tor-b\")) |= ($1)" "$(site_with_vlans_and_lag)" \
        > "$BATS_TEST_TMPDIR/site-lag.json"
    echo "$BATS_TEST_TMPDIR/site-lag.json"
}

# The real site with its ISL aggregated only on the ends named in $1.
site_with_isl_lag() {
    jq --argjson ends "$1" '
        (.devices[] | select(.role == "tor")) |= (
            del(.lags)
            | if (.name as $n | $ends | index($n)) then .lags = [{id: 1, name: "isl", ports: [31, 32]}] else . end)' \
        "$SITE_FILE" > "$BATS_TEST_TMPDIR/site-isl.json"
    echo "$BATS_TEST_TMPDIR/site-isl.json"
}

@test "a lag member the switch does not have stops the render" {
    site="$(site_with_lag_edit '.lags[0].ports = [29, 40]')"
    run fleet_render "$site" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"lag 1 port 40 does not exist on a TP-Link Omada SX3832"* ]]
}

@test "a lag member with no cable recorded on it stops the render" {
    site="$(site_with_lag_edit 'del(.ports["30"])')"
    run fleet_render "$site" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"lag 1 port 30 has no cable recorded on it"* ]]
}

@test "a lag across two peers stops the render" {
    site="$(site_with_lag_edit '.ports["30"].peer = "another-peer"')"
    run fleet_render "$site" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"lag 1 goes to more than one peer: another-peer, uplink-peer"* ]]
}

@test "two lags with one name stop the render, since the controller knows a lag by its name" {
    site="$(site_with_lag_edit '.ports["27"] = .ports["29"] | .ports["28"] = .ports["29"]
        | .lags += [{id: 2, name: "uplink", ports: [27, 28]}]')"
    run fleet_render "$site" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"2 lags are named uplink"* ]]
}

@test "a port in two lags, or a lag of one port, stops the render" {
    site="$(site_with_lag_edit '.lags += [{id: 2, name: "other", ports: [30]}]')"
    run fleet_render "$site" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"port 30 is in more than one lag"* ]]
    [[ "$output" == *"lag 2 has 1 port(s); a lag needs at least 2"* ]]
}

@test "a lag to a node takes one cable from each of the node's NICs" {
    jq '(.nodes[] | select(.name == "ber1-edge-b") | .links) |= map(
            if .switch == "ber1-tor-b" and .purpose == "data" then .port = 26 else . end)
        | (.nodes[] | select(.name == "ber1-edge-b") | .links) += [
            {switch: "ber1-tor-b", port: 27, media: "dac", purpose: "data", nic: "sfp28-1"}]
        | (.devices[] | select(.name == "ber1-tor-b")) .lags = [{id: 1, name: "edge-b", ports: [26, 27]}]' \
        "$SITE_FILE" > "$BATS_TEST_TMPDIR/site.json"
    run fleet_render "$BATS_TEST_TMPDIR/site.json" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"lag 1 has 2 cables from one NIC, sfp28-1"* ]]
}

@test "the ISL is a lag at both ends, and the lag carries the edge VLAN" {
    site="$SITE_FILE"
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render '$site' ber1-tor-b | fleet_context"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'interface port-channel 1\tswitchport general allowed vlan 4000 tagged'* ]]
    [[ "$output" == *$'interface ten-gigabitEthernet 1/0/31\tchannel-group 1 mode active'* ]]
    run fleet_render "$site" ber1-tor-a
    [ "$status" -eq 0 ]
}

@test "an ISL aggregated on one end only stops the render of both ends" {
    site="$(site_with_isl_lag '["ber1-tor-b"]')"
    run fleet_render "$site" ber1-tor-a
    [ "$status" -ne 0 ]
    [[ "$output" == *"the ISL to ber1-tor-a is a lag on one end only"* ]]
    [[ "$output" == *"the ISL to ber1-tor-b is a lag on one end only"* ]]
}

@test "an ISL cable recorded on one end only stops the render" {
    jq 'del(.devices[].lags) | (.devices[] | select(.name == "ber1-tor-a")) |= del(.ports["31"])' \
        "$SITE_FILE" > "$BATS_TEST_TMPDIR/site.json"
    run fleet_render "$BATS_TEST_TMPDIR/site.json" ber1-tor-a
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-tor-b: 2 ISL cable(s) to ber1-tor-a, which records 1 back"* ]]
}

@test "an ISL port left out of the ISL's lag stops the render" {
    jq '(.devices[] | select(.role == "tor")) |= (.ports["30"] = .ports["32"])' \
        "$SITE_FILE" > "$BATS_TEST_TMPDIR/site.json"
    run fleet_render "$BATS_TEST_TMPDIR/site.json" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"ISL port(s) 30 to ber1-tor-a are outside lag 1"* ]]
}

@test "a port with spanning tree off renders as no spanning-tree, with its own description" {
    site="$(site_with_vlans_and_lag)"
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render '$site' ber1-tor-b | fleet_context"
    [[ "$output" == *$'interface ten-gigabitEthernet 1/0/12\tno spanning-tree'* ]]
    [[ "$output" == *$'interface ten-gigabitEthernet 1/0/12\tdescription "no stp here"'* ]]
    [[ "$output" != *$'interface ten-gigabitEthernet 1/0/12\tspanning-tree'* ]]
}

@test "a port name the controller would refuse stops the render" {
    # "router uplink (WAN)" was refused by the controller on ber1-tor-a.
    jq '(.devices[] | select(.name == "ber1-tor-a") | .ports["24"].description) = "router uplink (WAN)"' \
        "$SITE_FILE" > "$BATS_TEST_TMPDIR/site.json"
    run fleet_render "$BATS_TEST_TMPDIR/site.json" ber1-tor-a
    [ "$status" -ne 0 ]
    [[ "$output" == *"names the controller would refuse: router uplink (WAN)"* ]]
}

@test "the object carries the configuration the reconciler writes, from the same data" {
    site="$(site_with_vlans_and_lag)"
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$site' ber1-tor-b | yq -o=json '.spec' | jq -c '{mac, managedBy, gateway: .config.gateway, vlans: .config.vlans, lags: .config.lags, ports: (.config.ports | length), p11: .config.ports[10].taggedVlans, p12: .config.ports[11], p29: .config.ports[28].description}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"mac":"d4:d6:df:03:d8:b2","managedBy":"controller","gateway":"192.168.0.10","vlans":[{"id":20,"name":"storage"}],"lags":[{"id":1,"name":"uplink","ports":[29,30]}],"ports":32,"p11":[],"p12":{"port":12,"description":"no stp here","spanningTree":false,"nativeVlan":1,"taggedVlans":[20]},"p29":"uplink"}' ]
}

@test "a VLAN's controller profile line is the controller's, with or without an address" {
    baseline="$(fleet_controller_baseline sx3832)"
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; printf '\tprofile network id 431253275 vid 20\n\tprofile network id 2004123914 vid 1 ip 192.168.0.1/24\ninterface port-channel 1\tspeed 10000\n\tlldp\n' | fleet_without_controller adds '$baseline'"
    [ "$output" = $'\tlldp' ]
}

@test "every switch's management address has the edge node as its gateway, as the controller writes it" {
    # Read off ber1-mgmt and both ToRs once the controller had written the
    # address with a gateway: the switch prints it on the address line. The
    # ToRs share the management segment with the edge node and ber1-mgmt hangs
    # off it; all three reach the controller that way.
    for device in ber1-tor-a ber1-tor-b ber1-mgmt; do
        run fleet_render "$SITE_FILE" "$device"
        [ "$status" -eq 0 ]
        address="$(jq -r --arg n "$device" '.devices[] | select(.name == $n) | .mgmt_address' "$SITE_FILE")"
        [[ "$output" == *"  ip address $address 255.255.255.0 gateway 192.168.0.10"* ]]
        [[ "$output" != *"ip route"* ]]
    done
}

@test "the fleet reaches a switch behind the edge through the edge node" {
    stub="$BATS_TEST_TMPDIR/jump"
    mkdir -p "$stub"
    cat > "$stub/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
sleep 0.2
printf 'sw>'
while IFS= read -r line; do
    line="${line%$'\r'}"
    printf '%s\r\n' "$line"
    [ "$line" = logout ] && exit 0
    printf '\r\nsw#'
done
STUB
    chmod +x "$stub/ssh"
    args="$BATS_TEST_TMPDIR/jump-args"
    run bash -c "
        set -uo pipefail
        export PATH=\"$stub:\$PATH\" FAKE_ARGS='$args'
        source '$FLEET_ROOT/lib/session.sh'
        SWITCH_JUMPS[192.0.2.13]='tuist@edge'
        trap switch_close EXIT
        switch_open 192.0.2.13 tuist /dev/null
    "
    run grep -c '^ProxyCommand=ssh -o BatchMode=yes -o ConnectTimeout=10 -W %h:%p tuist@edge$' "$args"
    [ "$output" = "1" ]
    # and a switch not behind it is dialled directly
    run bash -c "
        set -uo pipefail
        export PATH=\"$stub:\$PATH\" FAKE_ARGS='$args'
        source '$FLEET_ROOT/lib/session.sh'
        trap switch_close EXIT
        switch_open 192.0.2.12 tuist /dev/null
    "
    run grep -c 'ProxyCommand' "$args"
    [ "$output" = "0" ]
}

@test "an adopted switch logs in with the device account's password, which leaves no file behind" {
    # Adoption replaced ber1-mgmt's login with the controller's device account,
    # and the fleet key with it.
    stub="$BATS_TEST_TMPDIR/password"
    mkdir -p "$stub"
    cat > "$stub/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
printf '%s\n' "$SSH_ASKPASS" > "$FAKE_ARGS.askpass"
printf '%s\n' "${SSH_ASKPASS_REQUIRE:-}" > "$FAKE_ARGS.require"
"$SSH_ASKPASS" > "$FAKE_ARGS.password"
sleep 0.2
printf 'sw>'
while IFS= read -r line; do
    line="${line%$'\r'}"
    printf '%s\r\n' "$line"
    [ "$line" = logout ] && exit 0
    printf '\r\nsw#'
done
STUB
    cat > "$stub/op" <<'STUB'
#!/usr/bin/env bash
[ "$3" = "ber1 switch device account" ] && [ "$5" = "V1" ] || exit 1
echo '{"fields":[{"id":"username","value":"tuist"},{"id":"password","value":"Rk7#mQ2x!vL9pZ4w"}]}'
STUB
    chmod +x "$stub/ssh" "$stub/op"
    args="$BATS_TEST_TMPDIR/password-args"
    run bash -c "
        set -uo pipefail
        export PATH=\"$stub:\$PATH\" FAKE_ARGS='$args'
        source '$FLEET_ROOT/lib/session.sh'
        SWITCH_LOGIN_ITEMS[192.0.2.13]='ber1 switch device account'
        SWITCH_VAULT=V1
        trap switch_close EXIT
        switch_open 192.0.2.13 someone-else ~/.ssh/fleet
    "
    [ "$status" -eq 0 ]
    [ "$(cat "$args.password")" = 'Rk7#mQ2x!vL9pZ4w' ]
    [ "$(cat "$args.require")" = force ]
    run grep -cx 'tuist@192.0.2.13' "$args"
    [ "$output" = "1" ]
    run grep -cx 'PubkeyAuthentication=no' "$args"
    [ "$output" = "1" ]
    run grep -cx -- '-i' "$args"
    [ "$output" = "0" ]
    [ ! -e "$(dirname "$(cat "$args.askpass")")" ]
}

# ber1-mgmt as backed up after a factory reset, adoption with the factory login
# and one pass of the Open API, on 2026-09-23.
ADOPTED_FIXTURE="$BATS_TEST_DIRNAME/fixtures/ber1-mgmt-adopted.cfg"

@test "an adopted switch at its render, less the controller's own lines, is clean" {
    rendered="$BATS_TEST_TMPDIR/rendered.cfg"
    fleet_render "$SITE_FILE" ber1-mgmt > "$rendered"
    run fleet_diff "$rendered" "$ADOPTED_FIXTURE" rendered live
    [ "$status" -ne 0 ]
    run fleet_diff_adopted "$rendered" "$ADOPTED_FIXTURE" rendered live "$(fleet_controller_baseline tl-sg3452)"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a change the controller did not make is drift on an adopted switch" {
    rendered="$BATS_TEST_TMPDIR/rendered.cfg"
    changed="$BATS_TEST_TMPDIR/changed.cfg"
    fleet_render "$SITE_FILE" ber1-mgmt > "$rendered"
    sed 's/^spanning-tree mode rstp$/spanning-tree mode stp/; s/^  description "Port52"$/  description "someone"/' \
        "$ADOPTED_FIXTURE" > "$changed"
    run fleet_diff_adopted "$rendered" "$changed" rendered live "$(fleet_controller_baseline tl-sg3452)"
    [ "$status" -eq 1 ]
    [[ "$output" == *$'-\tspanning-tree mode rstp'* ]]
    [[ "$output" == *$'+\tspanning-tree mode stp'* ]]
    [[ "$output" == *$'+interface gigabitEthernet 1/0/52\tdescription "someone"'* ]]
}

@test "a description the render sets is drift until the switch carries it, whatever the controller named the port" {
    rendered="$BATS_TEST_TMPDIR/rendered.cfg"
    awk '{ print } $0 == "interface gigabitEthernet 1/0/1" { print "  description \"uplink\"" }' \
        <(fleet_render "$SITE_FILE" ber1-mgmt) > "$rendered"
    run fleet_diff_adopted "$rendered" "$ADOPTED_FIXTURE" rendered live "$(fleet_controller_baseline tl-sg3452)"
    [ "$status" -eq 1 ]
    [[ "$output" == *$'-interface gigabitEthernet 1/0/1\tdescription "uplink"'* ]]
    [[ "$output" != *'"Port1"'* ]]
}

@test "no SSH write path runs against a switch the controller has adopted" {
    for command in apply save replace recover; do
        run "$FLEET_ROOT/fleet.sh" "$command" ber1-mgmt --dry-run
        [ "$status" -ne 0 ]
        [[ "$output" == *"ber1-mgmt is adopted by the site's controller"* ]]
        [[ "$output" == *"rack:omada apply ber1-mgmt"* ]]
        [[ "$output" != *"test reached the real"* ]]
    done
}

@test "an adopted switch of a model nobody has measured under the controller is refused before connecting" {
    copy="$BATS_TEST_TMPDIR/fleet-copy"
    cp -R "$FLEET_ROOT" "$copy"
    rm "$copy/controller-baselines/sx3832.tsv"
    run env RACK_SITE=ber1 "$copy/fleet.sh" diff ber1-tor-b
    [ "$status" -eq 2 ]
    [[ "$output" == *"what the controller does to a sx3832 has not been measured"* ]]
    [[ "$output" != *"test reached the real"* ]]
}

@test "the switches the controller has adopted are the ones that log in with its device account" {
    declare -gA SWITCH_LOGIN_ITEMS=()
    fleet_load_logins "$SITE_FILE"
    [ "${#SWITCH_LOGIN_ITEMS[@]}" -eq 3 ]
    for address in 192.168.0.11 192.168.0.12 192.168.0.13; do
        [ "${SWITCH_LOGIN_ITEMS[$address]}" = "ber1 switch device account" ]
    done
    # the device account lives with the API client, in the vault the cluster reads
    [ "$SWITCH_VAULT" = "$(jq -r '.management.controller.vault' "$SITE_FILE")" ]
    [ "$SWITCH_VAULT" = "tuist-k8s-production" ]
}

@test "the jump comes from the site definition, for the devices behind the edge" {
    run jq -r '.management.edge.ssh as $j | .devices[] | select(.behind_edge and $j) | "\(.mgmt_address) \($j)"' "$SITE_FILE"
    [ "$output" = "192.168.0.13 tuist@ber1-edge-a" ]
}

# --- the edge node's files for the rack-edge chart ---------------------------

# The rendered management path run under sh, the way the pod runs it, against an
# `ip` shaped like ber1-edge-a's (two uplinks carrying default routes) and an nft
# that keeps what it loads. FAKE_DEFAULT_DEV adds a default route on another
# device; FAKE_FORWARD is what /proc/sys/net/ipv4/ip_forward reads; FAKE_ADDRS
# is what `ip -o -4 addr show` lists; FAKE_LINKS names the links `ip link show`
# finds.
edge_run_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/ip" <<'STUB'
#!/bin/sh
if [ "$*" = "route show default" ]; then
    echo "default via 192.168.0.1 dev enp2s0f0np0 proto dhcp src 192.168.0.157 metric 100"
    echo "default via 192.168.0.1 dev enp2s0f1np1 proto dhcp src 192.168.0.158 metric 100"
    [ -n "$FAKE_DEFAULT_DEV" ] && echo "default via 192.168.0.1 dev $FAKE_DEFAULT_DEV proto dhcp metric 50"
    exit 0
fi
if [ "$*" = "-o -4 addr show" ]; then
    [ -n "$FAKE_ADDRS" ] && printf '%s\n' "$FAKE_ADDRS"
    exit 0
fi
if [ "$1 $2" = "link show" ]; then
    case " $FAKE_LINKS " in *" $3 "*) exit 0;; esac
    exit 1
fi
echo "ip $*" >> "$FAKE_LOG"
STUB
    cat > "$dir/nft" <<'STUB'
#!/bin/sh
echo "nft $*" >> "$FAKE_LOG"
cat >> "$FAKE_LOG"
STUB
    cat > "$dir/ethtool" <<'STUB'
#!/bin/sh
echo "ethtool $*" >> "$FAKE_LOG"
STUB
    cat > "$dir/cat" <<'STUB'
#!/bin/sh
if [ "$1" = /proc/sys/net/ipv4/ip_forward ]; then echo "${FAKE_FORWARD:-1}"; else exec /bin/cat "$@"; fi
STUB
    chmod +x "$dir/ip" "$dir/nft" "$dir/ethtool" "$dir/cat"
    : > "$dir/log"
}

@test "the edge path translates every switch and advertises nothing, and leaves the floating addresses to keepalived" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_path "$(site_without_wan)"
    [ "$status" -eq 0 ]
    [[ "$output" == *'oifname "tailscale0" ip saddr { 192.168.0.12,192.168.0.11,192.168.0.13,192.168.50.0/24 } masquerade'* ]]
    [[ "$output" == *'oifname "tailscale0" ip saddr { 192.168.0.12,192.168.0.11,192.168.0.13,192.168.50.0/24 } tcp flags & (syn | rst) == syn tcp option maxseg size set rt mtu'* ]]
    [[ "$output" != *"advertise-routes"* ]]
    [[ "$output" != *"ip addr replace 192.168.0.10"* ]]
    [[ "$output" != *"ip addr replace 192.168.50.1"* ]]
    [[ "$output" != *"ip route replace"* ]]
}

@test "each edge's keepalived holds every floating address, prefers ber1-edge-a, and talks to the other edge alone" {
    source "$FLEET_ROOT/lib/edge.sh"
    site="$(site_without_wan)"
    run fleet_edge_keepalived "$site" ber1-edge-a
    [ "$status" -eq 0 ]
    [[ "$output" == *"router_id ber1-edge-a"* ]]
    [[ "$output" == *"interface vrrp0"* ]]
    [[ "$output" == *"priority 150"* ]]
    [[ "$output" == *"unicast_src_ip 10.255.255.1"* ]]
    [[ "$output" == *"unicast_peer {
    10.255.255.2
  }"* ]]
    [[ "$output" == *"track_interface {
    enp87s0
  }"* ]]
    [[ "$output" == *"192.168.0.10/24 dev enp87s0 noprefixroute"* ]]
    [[ "$output" == *"192.168.50.1/24 dev enp87s0"* ]]
    # only the switch behind the edge gets a host route, and only on the master
    [[ "$output" == *"192.168.0.13/32 dev enp87s0 src 192.168.0.10"* ]]
    [[ "$output" != *"192.168.0.11/32"* ]]
    [[ "$output" != *"wan0"* ]]
    # an advert counts only from the other edge's address and with the site's
    # password, which the rack-edge chart generates and mounts
    [[ "$output" == *"vrrp_check_unicast_src"* ]]
    [[ "$output" == *"
  include /etc/rack-edge-vrrp/authentication.conf
"* ]]
    run fleet_edge_keepalived "$SITE_FILE" ber1-edge-b
    [ "$status" -eq 0 ]
    [[ "$output" == *"priority 100"* ]]
    [[ "$output" == *"unicast_src_ip 10.255.255.2"* ]]
    [[ "$output" == *"unicast_peer {
    10.255.255.1
  }"* ]]
    run fleet_edge_keepalived "$SITE_FILE" ber1-store-a
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-store-a is not one of ber1.json's edges"* ]]
}

@test "a WAN address floats only through keepalived, so the standby holds none until it takes over" {
    source "$FLEET_ROOT/lib/edge.sh"
    for edge in ber1-edge-a ber1-edge-b; do
        run fleet_edge_keepalived "$SITE_FILE" "$edge"
        [ "$status" -eq 0 ]
        [[ "$output" == *"    149.6.170.31/31 dev wan0"$'\n'* ]]
        # the IPv6 address moves with the instance without being advertised
        [[ "$output" == *"  virtual_ipaddress_excluded {
    2001:978:2:b::4:11/127 dev wan0
  }"* ]]
        # the default routes go with the addresses
        [[ "$output" == *"    0.0.0.0/0 via 149.6.170.30 dev wan0"$'\n'* ]]
        [[ "$output" == *"    ::/0 via 2001:978:2:b::4:10 dev wan0"$'\n'* ]]
        # an edge whose WAN bond has no link never holds the WAN
        [[ "$output" == *"track_interface {
    enp87s0
    wan0
  }"* ]]
    done
    run fleet_edge_path "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"edge_vlan_bond wan0 4001"* ]]
    [[ "$output" != *"149.6.170."* ]]
    [[ "$output" != *"2001:978:"* ]]
    # the edge trunks carry the WAN VLAN tagged, and the WAN ports untagged and
    # alone, with no spanning tree towards the upstream
    for tor in ber1-tor-a ber1-tor-b; do
        run fleet_render "$SITE_FILE" "$tor"
        [ "$status" -eq 0 ]
        [ "$(awk '/^interface /{port = $3} /allowed vlan 4001 tagged/{printf "%s ", port}' <<<"$output")" = "1/0/25 1/0/26 1/0/31 1/0/32 1 " ]
        [[ "$output" == *'interface ten-gigabitEthernet 1/0/30
  description "wan '*'"
  no spanning-tree
  switchport general allowed vlan 4001 untagged
  switchport pvid 4001
  no switchport general allowed vlan 1
#'* ]]
    done
    [ "$(awk '/^interface /{port = $3} /allowed vlan 4001 untagged/{printf "%s ", port}' <<<"$output")" = "1/0/30 " ]
    run fleet_render "$SITE_FILE" ber1-tor-a
    [ "$(awk '/^interface /{port = $3} /allowed vlan 4001 untagged/{printf "%s ", port}' <<<"$output")" = "1/0/24 1/0/30 " ]
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$SITE_FILE' ber1-tor-a | yq -o=json '.spec.config' | jq -c '[.ports[] | select(.port == 24 or .port == 30) | {port, nativeVlan, taggedVlans, spanningTree}]'"
    [ "$output" = '[{"port":24,"nativeVlan":4001,"taggedVlans":[],"spanningTree":false},{"port":30,"nativeVlan":4001,"taggedVlans":[],"spanningTree":false}]' ]
    # without a WAN of its own the site keeps a WAN port on the management VLAN
    run fleet_render "$(site_without_wan)" ber1-tor-a
    [ "$status" -eq 0 ]
    [[ "$output" != *"4001"* ]]
    [[ "$output" == *'interface ten-gigabitEthernet 1/0/24
  description "wan copper"
  no spanning-tree
#'* ]]
}

@test "with a WAN of its own, an edge reaches the internet through it or through the other edge, and the switches through its uplinks" {
    source "$FLEET_ROOT/lib/edge.sh"
    bin="$BATS_TEST_TMPDIR/edge-wan"
    edge_run_stub "$bin"
    fleet_edge_path "$SITE_FILE" > "$bin/mgmt-path.sh"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" NODE_NAME=ber1-edge-b sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
    run cat "$bin/log"
    # nothing brings the uplinks up but this, once DHCP is off them
    [[ "$output" == *"ip link set enp2s0f1np1 up"* ]]
    [[ "$output" == *"ip link set enp2s0f0np0 up"* ]]
    [[ "$output" == *"ip link add link enp2s0f1np1 name wan0-1 type vlan id 4001"* ]]
    # the standby's way out is the master, at a metric keepalived's route beats
    [[ "$output" == *"ip route replace default via 10.255.255.1 dev vrrp0 metric 200 proto static"* ]]
    # the ToRs' management addresses over whichever uplink has link, and the
    # switch behind the edge left to keepalived's host route
    [[ "$output" == *"ip route replace 192.168.0.11/32 nexthop dev enp2s0f1np1 nexthop dev enp2s0f0np0"* ]]
    [[ "$output" == *"ip route replace 192.168.0.12/32 nexthop dev enp2s0f1np1 nexthop dev enp2s0f0np0"* ]]
    [[ "$output" != *"192.168.0.13/32"* ]]
    # the master translates the standby and the management segment onto the WAN
    [[ "$output" == *'oifname "wan0" ip saddr { 10.255.255.0/29, 192.168.0.0/24 } masquerade'* ]]
    # and the WAN lets in replies, ping, neighbour discovery and the tailnet's
    # direct path, and nothing else
    [[ "$output" == *'table inet tuist_rack_wan {
  chain input {
    type filter hook input priority filter;
    iifname "wan0" ct state established,related accept
    iifname "wan0" meta l4proto { icmp, ipv6-icmp } accept
    iifname "wan0" udp dport 41641 accept
    iifname "wan0" drop
  }
  chain forward {
    type filter hook forward priority filter;
    iifname "wan0" ct state established,related accept
    iifname "wan0" drop
  }
}'* ]]
    fleet_edge_path "$SITE_FILE" > "$bin/mgmt-path.sh"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" NODE_NAME=ber1-edge-a sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
    run cat "$bin/log"
    [[ "$output" == *"ip route replace default via 10.255.255.2 dev vrrp0 metric 200 proto static"* ]]
    # a site without a WAN routes nothing of its own and filters nothing
    run fleet_edge_path "$(site_without_wan)"
    [[ "$output" != *"ip route replace"* ]]
    [[ "$output" != *"wan0"* ]]
    [[ "$output" != *"peer_address"* ]]
}

@test "a WAN address that is not an address, or a gateway outside it, is refused at render" {
    source "$FLEET_ROOT/lib/edge.sh"
    site="$BATS_TEST_TMPDIR/badwan.json"
    jq '.management.edge.wan.gateway = "149.6.170.28"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"management.edge.wan.gateway '149.6.170.28' is not another address in 149.6.170.31/31"* ]]
    jq '.management.edge.wan.gateway = "149.6.170.31"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    jq '.management.edge.wan.address = "149.6.170.31"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not an address with its prefix length"* ]]
    jq '.management.edge.wan.address6 = "2001:978:2:b::4:11"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    jq '.management.edge.wan |= {vlan, address6, gateway6}' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"management.edge.wan has a gateway or an IPv6 address but no address"* ]]
    run fleet_edge_check "$SITE_FILE"
    [ "$status" -eq 0 ]
}

@test "the edges' VLANs are tagged only on the ports facing an edge's data links and on the ISL" {
    for tor in ber1-tor-a ber1-tor-b; do
        run fleet_render "$SITE_FILE" "$tor"
        [ "$status" -eq 0 ]
        [[ "$output" == *'vlan 4000
 name "edge-vrrp"'* ]]
        [ "$(awk '/^interface /{port = $3} /allowed vlan 4000 tagged/{printf "%s ", port}' <<<"$output")" = "1/0/25 1/0/26 1/0/31 1/0/32 1 " ]
    done
    run fleet_render "$SITE_FILE" ber1-mgmt
    [ "$status" -eq 0 ]
    [[ "$output" != *"4000"* ]]
    run fleet_render_k8s "$SITE_FILE" ber1-mgmt
    [[ "$output" != *"4000"* ]]
}

@test "VRRP membership is exactly the site's edges, on addresses in its prefix, over a VLAN the switches carry to them" {
    source "$FLEET_ROOT/lib/edge.sh"
    site="$BATS_TEST_TMPDIR/vrrp.json"
    jq '.management.edge.vrrp.members |= map(select(.node != "ber1-edge-b"))' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"members are ber1-edge-a, but the site's edges are ber1-edge-a, ber1-edge-b"* ]]
    jq '.management.edge.vrrp.members[1].address = "10.255.254.2"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-edge-b's VRRP address 10.255.254.2 is not in 10.255.255.0/29"* ]]
    jq '.management.edge.vrrp.members[1].address = "10.255.255.1"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"two edges share a VRRP address"* ]]
    jq '(.vlans[] | select(.id == 4000)) |= del(.carried_by)' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"vrrp.vlan 4000 is not a VLAN carried_by the edges"* ]]
    jq '.management.edge.wan.vlan = null' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"management.edge.wan has an address but no vlan"* ]]
    jq '.management.edge.vrrp.members[0].node = "ber1-edge-a;reboot"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
}

@test "the switch port's dnsmasq runs only while this edge holds the edge address there" {
    source "$FLEET_ROOT/lib/edge.sh"
    bin="$BATS_TEST_TMPDIR/edge-dhcp"
    mkdir -p "$bin"
    fleet_edge_dhcp_run "$SITE_FILE" > "$bin/dhcp.sh"
    holds="$bin/holds"
    log="$bin/log"
    : > "$log"
    cat > "$bin/ip" <<STUB
#!/bin/sh
[ -e "$holds" ] && echo "5: enp87s0    inet 192.168.0.10/24 scope global noprefixroute enp87s0"
exit 0
STUB
    cat > "$bin/dnsmasq" <<STUB
#!/bin/sh
echo "started \$*" >> "$log"
trap 'echo stopped >> "$log"; exit 0' TERM
while :; do /bin/sleep 0.1; done
STUB
    printf '#!/bin/sh\nexec /bin/sleep 0.1\n' > "$bin/sleep"
    chmod +x "$bin/ip" "$bin/dnsmasq" "$bin/sleep"

    PATH="$bin:$PATH" sh "$bin/dhcp.sh" &
    runner=$!
    /bin/sleep 1
    # nothing to serve from while keepalived has not given this node the address
    [ ! -s "$log" ]
    touch "$holds"
    /bin/sleep 1
    [ "$(grep -c '^started --no-daemon --conf-file=/etc/rack-edge/dnsmasq.conf$' "$log")" -eq 1 ]
    # the address moves to the other edge: dnsmasq goes with it
    rm "$holds"
    /bin/sleep 1
    grep -qx stopped "$log"
    # and comes back with the address, once
    touch "$holds"
    /bin/sleep 1
    [ "$(grep -c '^started' "$log")" -eq 2 ]
    kill "$runner"
    wait "$runner" || true
}

@test "a netbooting site hands UEFI firmware iPXE's Secure Boot shim, and iPXE its script, from the boot server" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_dhcp "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dhcp-match=set:netboot,option:client-arch,7"* ]]
    [[ "$output" == *"dhcp-match=set:netboot,option:client-arch,9"* ]]
    [[ "$output" == *"dhcp-userclass=set:ipxe,iPXE"* ]]
    [[ "$output" == *"dhcp-boot=tag:netboot,tag:!ipxe,snponly-shim.efi,,192.168.50.1"* ]]
    [[ "$output" == *$'\n'"dhcp-no-override"$'\n'* ]]
    [[ "$output" == *"dhcp-boot=tag:ipxe,boot.ipxe,,192.168.50.1"* ]]
    [[ "$output" != *"vendor-class"* ]]
    jq 'del(.management.edge.netboot)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nonetboot.json"
    run fleet_edge_dhcp "$BATS_TEST_TMPDIR/nonetboot.json"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dhcp-boot"* ]]
    [[ "$output" != *"dhcp-no-override"* ]]
}

@test "a netbooting site translates the provisioning range onto the uplinks, and only then" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_path "$(site_without_wan)"
    [ "$status" -eq 0 ]
    [[ "$output" == *'oifname != { "tailscale0", "enp87s0" } ip saddr 192.168.50.0/24 masquerade'* ]]
    jq 'del(.management.edge.netboot)' "$(site_without_wan)" > "$BATS_TEST_TMPDIR/nonetboot.json"
    run fleet_edge_path "$BATS_TEST_TMPDIR/nonetboot.json"
    [ "$status" -eq 0 ]
    [[ "$output" != *'ip saddr 192.168.50.0/24 masquerade'* ]]
    [[ "$output" == *'oifname "tailscale0" ip saddr { 192.168.0.12,192.168.0.11,192.168.0.13,192.168.50.0/24 } masquerade
    iifname "tailscale0" oifname "enp87s0" ip daddr { 192.168.0.14,192.168.0.15,192.168.0.16 } masquerade
    oifname != { "tailscale0", "machines0", "enp87s0" } ip saddr 10.10.0.0/24 masquerade
  }'* ]]
}

@test "netboot without a provisioning range is refused at render" {
    source "$FLEET_ROOT/lib/edge.sh"
    jq 'del(.management.edge.provisioning)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/noprov.json"
    run fleet_edge_dhcp "$BATS_TEST_TMPDIR/noprov.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"management.edge.netboot serves the provisioning range"* ]]
}

@test "the rendered edge path runs under sh and loads both tables in one go" {
    source "$FLEET_ROOT/lib/edge.sh"
    bin="$BATS_TEST_TMPDIR/edge-run"
    edge_run_stub "$bin"
    fleet_edge_path "$SITE_FILE" > "$bin/mgmt-path.sh"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" NODE_NAME=ber1-edge-a sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
    run cat "$bin/log"
    [[ "${lines[0]}" == "ip link set enp87s0 up" ]]
    [ "$(grep -c '^nft -f -$' "$bin/log")" -eq 1 ]
    [[ "$output" == *"delete table ip tuist_mgmt_path"* ]]
    [[ "$output" == *"delete table netdev tuist_rack_dhcp"* ]]
}

@test "the rendered edge path bonds this edge's VRRP VLAN over both uplinks and gives it this edge's address" {
    source "$FLEET_ROOT/lib/edge.sh"
    bin="$BATS_TEST_TMPDIR/edge-vrrp"
    edge_run_stub "$bin"
    fleet_edge_path "$(site_without_wan)" > "$bin/mgmt-path.sh"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" NODE_NAME=ber1-edge-b sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
    run cat "$bin/log"
    [[ "$output" == *"ip link add vrrp0 type bond mode active-backup miimon 100"* ]]
    [[ "$output" == *"ip link add link enp2s0f1np1 name vrrp0-1 type vlan id 4000"* ]]
    [[ "$output" == *"ip link add link enp2s0f0np0 name vrrp0-2 type vlan id 4000"* ]]
    [[ "$output" == *"ip link set vrrp0-1 master vrrp0"* ]]
    [[ "$output" == *"ip link set vrrp0-2 master vrrp0"* ]]
    [[ "$output" == *"ip addr replace 10.255.255.2/29 dev vrrp0"* ]]
    [[ "$output" != *"ip addr replace 192.168"* ]]
    # a second run finds the links it made and only puts back the address
    : > "$bin/log"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" NODE_NAME=ber1-edge-b FAKE_LINKS="vrrp0 vrrp0-1 vrrp0-2 machines0 machines0-1 machines0-2" sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
    run cat "$bin/log"
    [[ "$output" != *"ip link add"* ]]
    [[ "$output" == *"ip addr replace 10.255.255.2/29 dev vrrp0"* ]]
    # a node that is not one of the site's edges touches nothing
    : > "$bin/log"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" NODE_NAME=ber1-store-a sh "$bin/mgmt-path.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-store-a is not one of the site's edges"* ]]
    run cat "$bin/log"
    [[ "$output" != *"vrrp0"* ]]
}

@test "the rendered edge path gives both uplinks 4096-descriptor rings before a bond takes them" {
    source "$FLEET_ROOT/lib/edge.sh"
    bin="$BATS_TEST_TMPDIR/edge-rings"
    edge_run_stub "$bin"
    fleet_edge_path "$SITE_FILE" > "$bin/mgmt-path.sh"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" NODE_NAME=ber1-edge-a sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^ethtool ' "$bin/log")" -eq 2 ]
    [ "$(grep -n '^ethtool -G enp2s0f1np1 rx 4096 tx 4096$' "$bin/log" | cut -d: -f1)" -lt "$(grep -n ' master ' "$bin/log" | head -1 | cut -d: -f1)" ]
    [ "$(grep -n '^ethtool -G enp2s0f0np0 rx 4096 tx 4096$' "$bin/log" | cut -d: -f1)" -lt "$(grep -n ' master ' "$bin/log" | head -1 | cut -d: -f1)" ]
}

@test "the rendered edge path refuses a port that carries the node's default route" {
    source "$FLEET_ROOT/lib/edge.sh"
    bin="$BATS_TEST_TMPDIR/edge-uplink"
    edge_run_stub "$bin"
    fleet_edge_path "$SITE_FILE" > "$bin/mgmt-path.sh"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_DEFAULT_DEV=enp87s0 sh "$bin/mgmt-path.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"enp87s0 carries this node's default route"* ]]
    [ ! -s "$bin/log" ]
    # a route on a VLAN of the port is not the port itself
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_DEFAULT_DEV=enp87s0.10 NODE_NAME=ber1-edge-a sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
}

@test "the rendered edge path will not run with forwarding off" {
    source "$FLEET_ROOT/lib/edge.sh"
    bin="$BATS_TEST_TMPDIR/edge-forward"
    edge_run_stub "$bin"
    fleet_edge_path "$SITE_FILE" > "$bin/mgmt-path.sh"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_FORWARD=0 sh "$bin/mgmt-path.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ip_forward is off"* ]]
    [ ! -s "$bin/log" ]
}

@test "the rendered edge path takes the edge addresses off a port the site moved away from" {
    source "$FLEET_ROOT/lib/edge.sh"
    bin="$BATS_TEST_TMPDIR/edge-moved"
    edge_run_stub "$bin"
    fleet_edge_path "$SITE_FILE" > "$bin/mgmt-path.sh"
    addrs='5: enp89s0    inet 192.168.0.10/24 scope global noprefixroute enp89s0
5: enp89s0    inet 192.168.50.1/24 brd 192.168.50.255 scope global enp89s0
2: enp2s0f0np0    inet 192.168.0.157/24 brd 192.168.0.255 scope global dynamic enp2s0f0np0
3: enp87s0    inet 192.168.50.1/24 brd 192.168.50.255 scope global enp87s0'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_ADDRS="$addrs" NODE_NAME=ber1-edge-a sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
    run cat "$bin/log"
    [[ "$output" == *"ip addr del 192.168.0.10/24 dev enp89s0"* ]]
    [[ "$output" == *"ip addr del 192.168.50.1/24 dev enp89s0"* ]]
    [[ "$output" != *"del 192.168.0.157/24"* ]]
    [[ "$output" != *"del 192.168.50.1/24 dev enp87s0"* ]]
}

@test "a site whose edge node names no switch port renders no edge files" {
    source "$FLEET_ROOT/lib/edge.sh"
    jq 'del(.management.edge.interface)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/noport.json"
    run fleet_edge_dir "$BATS_TEST_TMPDIR/noport.json"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run fleet_edge_dir "$SITE_FILE"
    [[ "$output" == */helm/rack-edge/sites/ber1 ]]
}

@test "an edge port name that could smuggle a command is refused at render" {
    source "$FLEET_ROOT/lib/edge.sh"
    jq '.management.edge.interface = "enp87s0;true"' "$SITE_FILE" > "$BATS_TEST_TMPDIR/smuggle.json"
    run fleet_edge_path "$BATS_TEST_TMPDIR/smuggle.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not an interface name"* ]]
    run fleet_edge_dhcp "$BATS_TEST_TMPDIR/smuggle.json"
    [ "$status" -ne 0 ]
}

@test "render --check notices an edge file that no longer matches the site" {
    chart="$BATS_TEST_TMPDIR/chart"
    mkdir -p "$chart/sites"
    cp -R "$FLEET_ROOT/../helm/rack-edge/sites/ber1" "$chart/sites/"
    run env RACK_SITE=ber1 FLEET_EDGE_CHART="$chart" "$FLEET_ROOT/fleet.sh" render --check
    [ "$status" -eq 0 ]
    echo "dhcp-host=aa:bb:cc:dd:ee:ff,192.168.0.99,stray,infinite" >> "$chart/sites/ber1/dnsmasq.conf"
    run env RACK_SITE=ber1 FLEET_EDGE_CHART="$chart" "$FLEET_ROOT/fleet.sh" render --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"stale: "*"/sites/ber1/dnsmasq.conf"* ]]
}

@test "a freshly installed edge goes out over the VRRP VLAN the way its rack-edge pod later builds it" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_install "$SITE_FILE"
    [ "$status" -eq 0 ]
    install="$output"
    [[ "$install" == *"  ber1-edge-b:
    uplinks: [enp2s0f1np1, enp2s0f0np0]
    vrrp:
      vlan: 4000
      address: 10.255.255.2/29
      peer: 10.255.255.1"* ]]
    # every edge gets the pod's uplinks in the pod's order (vrrp0-<n> rides
    # the n-th), the pod's address and the pod's peer
    run fleet_edge_path "$SITE_FILE"
    [ "$status" -eq 0 ]
    local edges=0 line node address peer uplinks
    while IFS= read -r line; do
        node="$(sed -E 's/^  ([a-z0-9-]+)\) .*/\1/' <<<"$line")"
        address="$(sed -E 's/.* vrrp_address=([^ ]+) .*/\1/' <<<"$line")"
        peer="$(sed -E 's/.* peer_address=([^ ]+) .*/\1/' <<<"$line")"
        uplinks="$(sed -E 's/.* uplinks="([^"]*)".*/\1/' <<<"$line")"
        [[ "$install" == *"  $node:
    uplinks: [${uplinks// /, }]
    vrrp:
      vlan: 4000
      address: $address
      peer: $peer"* ]]
        edges=$((edges + 1))
    done < <(grep -E '^  ber1-edge-[a-z]+\) vrrp_address=' <<<"$output")
    [ "$edges" -eq 2 ]
    # and the route the pod puts back is the one networkd gives the install,
    # protocol included, so a restart of networkd adds no second one
    [[ "$output" == *'ip route replace default via "$peer_address" dev vrrp0 metric 200 proto static'* ]]
    [ "$(grep -c '^  ber1-edge-' <<<"$install")" -eq 2 ]
}

@test "a site with no WAN gives its edges' installs no way out over VRRP, so they keep DHCP on their uplinks" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_install "$(site_without_wan)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"edges: {}"* ]]
    [[ "$output" != *"vrrp"* ]]
}

@test "render --check notices an edge install the tuist chart reads that no longer matches the site" {
    chart="$BATS_TEST_TMPDIR/chart"
    sites="$BATS_TEST_TMPDIR/rack-sites"
    mkdir -p "$chart/sites" "$sites"
    cp -R "$FLEET_ROOT/../helm/rack-edge/sites/ber1" "$chart/sites/"
    cp "$FLEET_ROOT/../helm/tuist/rack-sites/ber1.yaml" "$sites/"
    run env RACK_SITE=ber1 FLEET_EDGE_CHART="$chart" FLEET_RACK_SITES="$sites" "$FLEET_ROOT/fleet.sh" render --check
    [ "$status" -eq 0 ]
    sed -i.bak 's/peer: 10.255.255.1$/peer: 10.255.255.3/' "$sites/ber1.yaml"
    run env RACK_SITE=ber1 FLEET_EDGE_CHART="$chart" FLEET_RACK_SITES="$sites" "$FLEET_ROOT/fleet.sh" render --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"stale: "*"/rack-sites/ber1.yaml"* ]]
}

# --- the machines segment ----------------------------------------------------
#
# The runners sit on a VLAN of their own behind the edges: untagged on their
# ToR port, tagged only toward the edges, with the edges' DHCP handing each its
# RackHost's address and both edges routing the tailnet to it.

@test "a runner's port carries the machines VLAN untagged and nothing else, and only the edges' ports and the ISL tag it" {
    run fleet_render "$SITE_FILE" ber1-tor-b
    [ "$status" -eq 0 ]
    [[ "$output" == *'vlan 10
 name "machines"'* ]]
    [[ "$output" == *'interface ten-gigabitEthernet 1/0/2
  spanning-tree
  switchport general allowed vlan 10 untagged
  switchport pvid 10
  no switchport general allowed vlan 1
#'* ]]
    # tagged exactly where the edges' VRRP VLAN is: their ports and the ISL
    tagged_on() { awk -v v="$1" '/^interface /{port = $2 " " $3} $0 ~ "allowed vlan " v " tagged" {printf "%s, ", port}'; }
    [[ "$(tagged_on 10 <<<"$output")" == *"1/0/25, "*"1/0/26, "* ]]
    [ "$(tagged_on 10 <<<"$output")" = "$(tagged_on 4000 <<<"$output")" ]
    run fleet_render "$SITE_FILE" ber1-tor-a
    [[ "$(tagged_on 10 <<<"$output")" == *"1/0/25, "*"1/0/26, "* ]]
    [ "$(tagged_on 10 <<<"$output")" = "$(tagged_on 4000 <<<"$output")" ]
    # on ToR A only the storage node sits on the segment
    [ "$(awk '/^interface /{port = $2 " " $3} /allowed vlan 10 untagged/ {print port}' <<<"$output")" = "ten-gigabitEthernet 1/0/27" ]
    run fleet_render "$SITE_FILE" ber1-mgmt
    [[ "$output" != *"vlan 10"* ]]
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$SITE_FILE' ber1-tor-b | yq -o=json '.spec.config' | jq -c '[(.ports[] | select(.port == 2) | {nativeVlan, taggedVlans}), ([.vlans[].id])]'"
    [ "$status" -eq 0 ]
    [ "$output" = '[{"nativeVlan":10,"taggedVlans":[]},[10,4000,4001]]' ]
    # a site without the segment leaves the runner on the management VLAN, and
    # the spare WAN optic's port is the one port with a native VLAN of its own
    jq '.management.edge.machines = {vlan: null, gateway: null} | .vlans |= map(select(.id != 10))' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nomachines.json"
    run fleet_render "$BATS_TEST_TMPDIR/nomachines.json" ber1-tor-b
    [ "$status" -eq 0 ]
    [[ "$output" != *"vlan 10"* ]]
    [ "$(grep -c untagged <<<"$output")" -eq 1 ]
}

@test "each edge has an address of its own on the machines segment, and only the master holds the gateway" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_path "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ber1-edge-a) vrrp_address=10.255.255.1/29 machines_address=10.10.0.2/24 peer_address=10.255.255.2 uplinks="* ]]
    [[ "$output" == *"ber1-edge-b) vrrp_address=10.255.255.2/29 machines_address=10.10.0.3/24 peer_address=10.255.255.1 uplinks="* ]]
    [[ "$output" != *"10.10.0.1"* ]]
    for edge in ber1-edge-a ber1-edge-b; do
        run fleet_edge_keepalived "$SITE_FILE" "$edge"
        [ "$status" -eq 0 ]
        # a /32, so giving it up never takes the edge's own address with it
        [[ "$output" == *"    10.10.0.1/32 dev machines0"$'\n'* ]]
        [[ "$output" != *"10.10.0.2"* ]]
        [[ "$output" != *"10.10.0.3"* ]]
    done
    bin="$BATS_TEST_TMPDIR/edge-machines"
    edge_run_stub "$bin"
    fleet_edge_path "$SITE_FILE" > "$bin/mgmt-path.sh"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" NODE_NAME=ber1-edge-b sh "$bin/mgmt-path.sh"
    [ "$status" -eq 0 ]
    run cat "$bin/log"
    [[ "$output" == *"ip link add link enp2s0f1np1 name machines0-1 type vlan id 10"* ]]
    [[ "$output" == *"ip link add link enp2s0f0np0 name machines0-2 type vlan id 10"* ]]
    [[ "$output" == *"ip addr replace 10.10.0.3/24 dev machines0"* ]]
}

@test "a machine reaches the internet through its gateway and nothing the edges keep for themselves" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_path "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *'oifname != { "tailscale0", "machines0", "enp87s0" } ip saddr 10.10.0.0/24 masquerade'* ]]
    [[ "$output" == *'delete table inet tuist_rack_machines'* ]]
    [[ "$output" == *'iifname "machines0" oifname { "tailscale0", "vrrp0", "enp87s0" } drop'* ]]
    [[ "$output" == *'iifname "machines0" ip daddr { 192.168.0.0/24, 192.168.50.0/24, 10.255.255.0/29 } drop'* ]]
    # of the edge itself, a machine reaches DHCP and ping and nothing else
    [[ "$output" == *'    iifname "machines0" udp dport 67 accept
    iifname "machines0" icmp type echo-request accept
    iifname "machines0" drop'* ]]
    # and all of it in the one transaction the path already loads
    [ "$(grep -c "^nft -f - <<'NFT'$" <<<"$output")" -eq 1 ]
    jq '.management.edge.machines = {vlan: null, gateway: null} | .vlans |= map(select(.id != 10))' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nomachines.json"
    run fleet_edge_path "$BATS_TEST_TMPDIR/nomachines.json"
    [ "$status" -eq 0 ]
    [[ "$output" != *"machines0"* ]]
    [[ "$output" != *"10.10.0.0/24"* ]]
}

@test "every machine gets its RackHost's address against the MAC of its link, from either edge" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_machines_dhcp "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\ninterface=machines0\n'* ]]
    [[ "$output" == *"dhcp-range=set:machines,10.10.0.0,static,255.255.255.0,infinite"* ]]
    [[ "$output" == *"dhcp-option=tag:machines,option:router,10.10.0.1"* ]]
    [[ "$output" == *"dhcp-option=tag:machines,option:dns-server,1.1.1.1,8.8.8.8"* ]]
    [[ "$output" == *"dhcp-host=bc:74:ea:b7:76:b0,10.10.0.101,ber1-runner-b01,infinite"* ]]
    [[ "$output" == *"dhcp-host=bc:74:ea:b2:96:1d,10.10.0.102,ber1-runner-b02,infinite"* ]]
    [[ "$output" == *"dhcp-host=bc:74:ea:be:0b:56,10.10.0.103,ber1-runner-b03,infinite"* ]]
    # both edges answer, so neither NAKs a request the machine sent the other
    [[ "$output" != *"dhcp-authoritative"* ]]
    # its own process, one interface each, so both share port 67
    [ "$(grep -c '^interface=' <<<"$output")" -eq 1 ]
    # and no lease file: a kept lease holds an address against a MAC the site
    # no longer reserves it for, and dnsmasq refuses it to the one it now does
    [[ "$output" == *$'\nleasefile-ro\n'* ]]
    [[ "$output" != *"dhcp-leasefile"* ]]
    run fleet_edge_dhcp "$SITE_FILE"
    [[ "$output" == *"dhcp-authoritative"* ]]
    [[ "$output" != *"machines"* ]]
    [ "$(grep -c '^interface=' <<<"$output")" -eq 1 ]
    # the address is the RackHost's, never a copy in the site definition
    values="$BATS_TEST_TMPDIR/values.yaml"
    yq '(.rackFleet.hosts[] | select(.name == "ber1-runner-b01")).address = "10.10.0.150"' "$FLEET_RACK_VALUES" > "$values"
    FLEET_RACK_VALUES="$values" run fleet_edge_machines_dhcp "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dhcp-host=bc:74:ea:b7:76:b0,10.10.0.150,ber1-runner-b01,infinite"* ]]
    # a site without the segment serves nothing there
    jq '.management.edge.machines = {vlan: null, gateway: null} | .vlans |= map(select(.id != 10))' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nomachines.json"
    run fleet_edge_machines_dhcp "$BATS_TEST_TMPDIR/nomachines.json"
    [ "$status" -eq 0 ]
    [[ "$output" != *"interface="* ]]
    [[ "$output" != *"dhcp-range"* ]]
}

@test "a storage node sits on the machines segment at its RackLinuxHost's address, beside the runners it serves" {
    run fleet_render "$SITE_FILE" ber1-tor-a
    [ "$status" -eq 0 ]
    [[ "$output" == *'interface ten-gigabitEthernet 1/0/27
  spanning-tree
  switchport general allowed vlan 10 untagged
  switchport pvid 10
  no switchport general allowed vlan 1
#'* ]]
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_machines_dhcp "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dhcp-host=38:05:25:3a:de:65,10.10.0.11,ber1-store-a,infinite"* ]]
    values="$BATS_TEST_TMPDIR/values.yaml"
    # its caches move with it
    yq '(.rackLinuxFleet.hosts[] | select(.hostname == "ber1-store-a")).address = "10.10.0.12" | .rackFleet.vmCacheGatewayCIDRs = ["10.10.0.12/32"] | .rackFleet.imageCache.nodes[0].address = "10.10.0.12"' "$FLEET_RACK_VALUES" > "$values"
    FLEET_RACK_VALUES="$values" run fleet_edge_machines_dhcp "$SITE_FILE"
    [[ "$output" == *"dhcp-host=38:05:25:3a:de:65,10.10.0.12,ber1-store-a,infinite"* ]]
    # a Linux node on the segment needs a declared host with an address
    yq 'del((.rackLinuxFleet.hosts[] | select(.hostname == "ber1-store-a")).address)' "$FLEET_RACK_VALUES" > "$values"
    FLEET_RACK_VALUES="$values" run fleet_edge_check_machines "$SITE_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-store-a's RackLinuxHost has no address"* ]]
    yq 'del(.rackLinuxFleet.hosts[] | select(.hostname == "ber1-store-a"))' "$FLEET_RACK_VALUES" > "$values"
    FLEET_RACK_VALUES="$values" run fleet_edge_check_machines "$SITE_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-store-a is on the machines segment and is neither a RackHost nor a RackLinuxHost"* ]]
}

@test "the rack's cache gateways and image caches are its storage nodes, at their RackLinuxHosts' addresses" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_check_rack_caches "$SITE_FILE"
    [ "$status" -eq 0 ]
    values="$BATS_TEST_TMPDIR/values.yaml"
    # an image cache at an address its node does not hold
    yq '.rackFleet.imageCache.nodes[0].address = "10.10.0.12"' "$FLEET_RACK_VALUES" > "$values"
    FLEET_RACK_VALUES="$values" run fleet_edge_check_rack_caches "$SITE_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"the image cache on ber1-store-a is at 10.10.0.12, but its RackLinuxHost is at 10.10.0.11"* ]]
    # an image cache on something that is not a storage node in the rack
    yq '.rackFleet.imageCache.nodes = [{"name": "ber1-store-b", "address": "10.10.0.12"}, {"name": "ber1-edge-a", "address": "10.10.0.2"}]' "$FLEET_RACK_VALUES" > "$values"
    FLEET_RACK_VALUES="$values" run fleet_edge_check_rack_caches "$SITE_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"the image cache on ber1-store-b is not on a storage node of this site that is in the rack"* ]]
    [[ "$output" == *"the image cache on ber1-edge-a is not on a storage node of this site that is in the rack"* ]]
    # a cache gateway that is not a storage node's address
    yq '.rackFleet.vmCacheGatewayCIDRs = ["10.10.0.2/32", "10.10.0.0/24"]' "$FLEET_RACK_VALUES" > "$values"
    FLEET_RACK_VALUES="$values" run fleet_edge_check_rack_caches "$SITE_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cache gateway 10.10.0.2/32 is not the address of a storage node"* ]]
    [[ "$output" == *"cache gateway 10.10.0.0/24 is not the address of a storage node"* ]]
}

# Runs a rendered tailnet-routes.sh with the node's tailscale and ip stubbed:
# FAKE_EDGE_ADDRESS is what the switch port holds. Prints what was advertised.
routes_advertised() {
    local script="$1" bin="$BATS_TEST_TMPDIR/routes-bin"
    mkdir -p "$bin"
    cat > "$bin/ip" <<'STUB'
#!/bin/sh
[ "$*" = "-4 -o addr show dev enp87s0" ] || exit 1
[ -n "$FAKE_EDGE_ADDRESS" ] && echo "3: enp87s0    inet $FAKE_EDGE_ADDRESS scope global noprefixroute enp87s0"
exit 0
STUB
    cat > "$bin/tailscale" <<'STUB'
#!/bin/sh
for arg; do case "$arg" in --advertise-routes=*) echo "${arg#--advertise-routes=}";; esac; done
STUB
    chmod +x "$bin/ip" "$bin/tailscale"
    PATH="$bin:$PATH" sh "$script"
}

@test "the edges advertise each machine's address to the tailnet, and nothing else" {
    source "$FLEET_ROOT/lib/edge.sh"
    script="$BATS_TEST_TMPDIR/routes.sh"
    # a site whose power devices are still planned advertises only the machines
    jq '(.nodes[] | select(.role == "power")) |= (.status = "planned")' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nopower.json"
    fleet_edge_routes "$BATS_TEST_TMPDIR/nopower.json" > "$script"
    run grep -c 'ip ' "$script"
    [ "$output" = "0" ]
    FAKE_EDGE_ADDRESS=192.168.0.10/24 run routes_advertised "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "10.10.0.101/32,10.10.0.102/32,10.10.0.103/32,10.10.0.104/32,10.10.0.105/32,10.10.0.106/32,10.10.0.107/32,10.10.0.108/32,10.10.0.109/32" ]
    # a mini still planned has no route until it is racked
    jq '.nodes += [{name: "ber1-runner-b10", role: "runner", hardware: "mac-mini", status: "planned", rack_host: "ber1-runner-b01",
          links: [{switch: "ber1-tor-b", port: 11, media: "copper", nic: "en0", purpose: "data"}]}]' "$BATS_TEST_TMPDIR/nopower.json" > "$BATS_TEST_TMPDIR/planned.json"
    fleet_edge_routes "$BATS_TEST_TMPDIR/planned.json" > "$script"
    run routes_advertised "$script"
    [ "$output" = "10.10.0.101/32,10.10.0.102/32,10.10.0.103/32,10.10.0.104/32,10.10.0.105/32,10.10.0.106/32,10.10.0.107/32,10.10.0.108/32,10.10.0.109/32" ]
    # a site without the segment withdraws whatever an edge advertised
    jq '.management.edge.machines = {vlan: null, gateway: null} | .vlans |= map(select(.id != 10))' "$BATS_TEST_TMPDIR/nopower.json" > "$BATS_TEST_TMPDIR/nomachines.json"
    fleet_edge_routes "$BATS_TEST_TMPDIR/nomachines.json" > "$script"
    run routes_advertised "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "only the edge holding the switch port's address advertises the power devices behind it" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_power "$SITE_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = $'192.168.0.14\n192.168.0.15\n192.168.0.16' ]
    script="$BATS_TEST_TMPDIR/routes.sh"
    fleet_edge_routes "$SITE_FILE" > "$script"
    # the master: the machines, and a /32 per installed power device on ber1-mgmt
    FAKE_EDGE_ADDRESS=192.168.0.10/24 run routes_advertised "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "10.10.0.101/32,10.10.0.102/32,10.10.0.103/32,10.10.0.104/32,10.10.0.105/32,10.10.0.106/32,10.10.0.107/32,10.10.0.108/32,10.10.0.109/32,192.168.0.14/32,192.168.0.15/32,192.168.0.16/32" ]
    # the standby has no route to them, so it advertises the machines alone
    run routes_advertised "$script"
    [ "$status" -eq 0 ]
    [ "$output" = "10.10.0.101/32,10.10.0.102/32,10.10.0.103/32,10.10.0.104/32,10.10.0.105/32,10.10.0.106/32,10.10.0.107/32,10.10.0.108/32,10.10.0.109/32" ]
    # an address that merely starts like the edge's is not it
    FAKE_EDGE_ADDRESS=192.168.0.100/24 run routes_advertised "$script"
    [ "$output" = "10.10.0.101/32,10.10.0.102/32,10.10.0.103/32,10.10.0.104/32,10.10.0.105/32,10.10.0.106/32,10.10.0.107/32,10.10.0.108/32,10.10.0.109/32" ]
    # a planned PDU, and one whose management link is not behind the edge, are not advertised
    jq '(.nodes[] | select(.name == "ber1-pdu-a")) |= (.mgmt_address = "192.168.0.17")
        | (.nodes[] | select(.name == "ber1-ats-1") | .links[0].switch) = "ber1-tor-a"' "$SITE_FILE" > "$BATS_TEST_TMPDIR/power.json"
    run fleet_edge_power "$BATS_TEST_TMPDIR/power.json"
    [ "$output" = $'192.168.0.15\n192.168.0.16' ]
}

@test "the tailnet reaches a power device through the master's switch port, translated to the edge address" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_keepalived "$SITE_FILE" ber1-edge-b
    [ "$status" -eq 0 ]
    [[ "$output" == *"192.168.0.16/32 dev enp87s0 src 192.168.0.10"* ]]
    [[ "$output" == *"192.168.0.14/32 dev enp87s0 src 192.168.0.10"* ]]
    run fleet_edge_path "$SITE_FILE"
    [ "$status" -eq 0 ]
    # the PDU's gateway is not an edge, so a reply to a tailnet address would
    # never come back: it is translated to the edge address, on-link for it
    [[ "$output" == *'iifname "tailscale0" oifname "enp87s0" ip daddr { 192.168.0.14,192.168.0.15,192.168.0.16 } masquerade'* ]]
    [[ "$output" == *'oifname "tailscale0" ip saddr { 192.168.0.14,192.168.0.15,192.168.0.16 } tcp flags & (syn | rst) == syn tcp option maxseg size set rt mtu'* ]]
    # without power devices there is no rule naming an empty set, which nft refuses
    jq '(.nodes[] | select(.role == "power")) |= del(.mgmt_address)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nopower.json"
    run fleet_edge_path "$BATS_TEST_TMPDIR/nopower.json"
    [ "$status" -eq 0 ]
    [[ "$output" != *'iifname "tailscale0" oifname "enp87s0"'* ]]
    [[ "$output" != *"{  }"* ]]
}

@test "a power device's address outside the management prefix is refused at render" {
    source "$FLEET_ROOT/lib/edge.sh"
    jq '(.nodes[] | select(.name == "ber1-pdu-b")) |= (.mgmt_address = "10.0.0.16; reboot")' "$SITE_FILE" > "$BATS_TEST_TMPDIR/badpower.json"
    run fleet_edge_routes "$BATS_TEST_TMPDIR/badpower.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"power device address 10.0.0.16; reboot is not in the management prefix 192.168.0.0/24"* ]]
    jq '(.nodes[] | select(.name == "ber1-pdu-b")) |= (.mac = "00:20:85:D7:00:CA")' "$SITE_FILE" > "$BATS_TEST_TMPDIR/badmac.json"
    run fleet_edge_dhcp "$BATS_TEST_TMPDIR/badmac.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-pdu-b's mac '00:20:85:D7:00:CA' is not a MAC in lower case"* ]]
}

