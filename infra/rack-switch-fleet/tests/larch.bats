#!/usr/bin/env bats
# Rack 2: a site with no management switch, whose management ports are cabled
# into the opposite ToR on a management VLAN the edges carry, whose ToRs are
# PicOS and whose dual-PSU gear takes both feeds directly.

load helpers

setup() {
    source "$FLEET_ROOT/lib/config.sh"
    SITE_FILE="$(fleet_site_file ber1)"
    LARCH="$(fleet_site_file larch)"
}

teardown() { rm -f "$FLEET_ROOT/sites/larch-edit.json"; }

edge_sh() { bash -c "source '$FLEET_ROOT/lib/config.sh'; source '$FLEET_ROOT/lib/edge.sh'; $1"; }

# larch with a jq edit applied, as a site of its own.
larch_with() {
    jq "$1" "$LARCH" > "$FLEET_ROOT/sites/larch-edit.json"
    echo "$FLEET_ROOT/sites/larch-edit.json"
}

# larch once the second ToR's MAC and the controller's key are in: both edges
# provision their ToR.
larch_ready() {
    larch_with '
        (.devices[] | select(.name == "larch-tor-b")).mac = "64:9d:99:d9:81:fe"
        | (.nodes[] | select(.name == "larch-edge-a")).tor_management = {switch: "larch-tor-a", nic: "lan1", address: "192.168.61.1/30"}
        | (.nodes[] | select(.name == "larch-edge-b")).tor_management = {switch: "larch-tor-b", nic: "lan1", address: "192.168.61.5/30"}
        | .management.picos.authorized_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGtoh9Tz1HAy1HdkAXn5W2K8qpmAZdQ3ow2V8L4gBP2m rack-switch-controller"]'
}

@test "rack 2 passes the site checks" {
    run fleet_check_site "$LARCH"
    [ "$status" -eq 0 ]
    run edge_sh "fleet_edge_check '$LARCH'"
    [ "$status" -eq 0 ]
}

@test "a management link on the ToR a node's data link is on is refused" {
    site="$(larch_with '(.nodes[] | select(.name == "larch-store-a") | .links[] | select(.purpose == "management")) |= (.switch = "larch-tor-a" | .port = 22)')"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"larch-store-a: management link goes to larch-tor-a, the ToR it depends on; it belongs on the opposite one"* ]]
}

@test "an edge's BMC on the ToR it provisions is refused" {
    site="$(larch_ready)"
    jq '(.nodes[] | select(.name == "larch-edge-a") | .links[] | select(.purpose == "management")) |= (.switch = "larch-tor-a" | .port = 22)' \
        "$site" > "$site.new" && mv "$site.new" "$site"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"larch-edge-a: management link goes to larch-tor-a, the ToR it depends on"* ]]
}

@test "a PDU's card on the ToR its minis are on is refused" {
    site="$(larch_with '.nodes += [{name: "larch-runner-01", role: "runner", hardware: "mac-mini", status: "planned", pdu: "larch-pdu-a",
            links: [{switch: "larch-tor-b", port: 1, media: "copper", nic: "en0", purpose: "data"}]}]')"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"larch-pdu-a: management link goes to larch-tor-b, the ToR it depends on"* ]]
    # Its transfer switch is on the same side.
    [[ "$output" == *"larch-ats-a: management link goes to larch-tor-b"* ]]
}

@test "a management link to something that is not a ToR is refused" {
    site="$(larch_with '(.nodes[] | select(.name == "larch-ats-a") | .links[0]).switch = "larch-mgmt"')"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"larch-ats-a: management link goes to larch-mgmt, which is not one of the ToRs"* ]]
}

@test "dual-PSU gear names both feeds, and only the site's" {
    site="$(larch_with '(.devices[] | select(.name == "larch-tor-a")).feeds = ["feed-a", "feed-c"]')"
    run fleet_check_power "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"larch-tor-a: feed feed-c is not one of the site's feeds"* ]]
    site="$(larch_with '(.devices[] | select(.name == "larch-tor-a")).feeds = ["feed-a", "feed-a"]')"
    run fleet_check_power "$site"
    [[ "$output" == *"are not distinct feeds"* ]]
    site="$(larch_with '(.nodes[] | select(.name == "larch-edge-a")).ats = "larch-ats-a"')"
    run fleet_check_power "$site"
    [[ "$output" == *"larch-edge-a: names feeds and an ats or pdu"* ]]
    site="$(larch_with 'del(.devices[] | select(.name == "larch-tor-a") | .feeds)')"
    run fleet_check_power "$site"
    [[ "$output" == *"larch-tor-a: one of the tor pair, but names no ats, pdu or feeds"* ]]
}

@test "the cable schedule has a cord from each feed to each PSU" {
    run fleet_cable_schedule "$LARCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| feed-a |  | larch-tor-a | psu-1 | power | feed |"* ]]
    [[ "$output" == *"| feed-b |  | larch-tor-a | psu-2 | power | feed |"* ]]
}

@test "only ports with a management link are untagged on the management VLAN" {
    run fleet_sh "fleet_render_k8s '$LARCH' larch-tor-a"
    [ "$status" -eq 0 ]
    ports="$(yq -o=json '.spec.config.ports' <<<"$output")"
    port() { jq -c --argjson n "$1" '.[] | select(.port == $n) | [.nativeVlan, .taggedVlans]' <<<"$ports"; }
    # A mini's port: untagged on the machines VLAN, not management.
    [ "$(port 1)" = '[10,[]]' ]
    # A port with nothing recorded on it: on no segment.
    [ "$(port 6)" = '[1,[]]' ]
    # larch-pdu-b's card and larch-edge-b's BMC.
    [ "$(port 23)" = '[20,[]]' ]
    [ "$(port 28)" = '[20,[]]' ]
    # larch-edge-a's leg and the ISL carry the management VLAN tagged, not untagged too.
    [ "$(port 29)" = '[1,[10,20,4000,4001,4002]]' ]
    [ "$(port 25)" = '[1,[10,20,4000,4001,4002]]' ]
    [ "$(port 27)" = '[4001,[]]' ]
    # larch-store-a's leg, on the machines VLAN.
    [ "$(port 31)" = '[10,[]]' ]
}

@test "a site with a management switch keeps its ports on the management VLAN" {
    run fleet_sh "fleet_port_settings '$SITE_FILE' \"\$(fleet_device '$SITE_FILE' ber1-tor-a)\" \"\$(fleet_model sx3832)\""
    [ "$status" -eq 0 ]
    ! awk -F'\037' '$8 == "1"' <<<"$output" | grep -q .
}

@test "the edge reaches the management VLAN over its uplinks, as mgmt0" {
    run edge_sh "fleet_edge_path '$LARCH'"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'edge_vlan_bond vrrp0 4000\nedge_vlan_bond mgmt0 20\n'* ]]
    [[ "$output" != *"ip link set mgmt0 up"* ]]
    # A PicOS ToR's management port is out of band, so it is not routed over the uplinks.
    [[ "$output" != *"ip route replace 192.168.61."* ]]
    bash -n <<<"$output"
}

@test "a management VLAN on the uplinks needs mgmt0 as the edge's interface" {
    site="$(larch_with '.management.edge.interface = "eno2"')"
    run edge_sh "fleet_edge_check '$site'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"management.edge.interface is mgmt0"* ]]
}

@test "the power devices on the ToRs are reached through mgmt0 once installed" {
    site="$(larch_with '(.nodes[] | select(.name == "larch-pdu-a")) |= (.status = "installed" | .mac = "00:20:85:00:00:01") | (.nodes[] | select(.name == "larch-pdu-b")) |= (.status = "planned" | del(.mac))')"
    run edge_sh "fleet_edge_power_devices '$site'"
    [[ "$output" == *"larch-pdu-a|00:20:85:00:00:01|192.168.60.16"* ]]
    [[ "$output" != *"larch-pdu-b"* ]]
    run edge_sh "fleet_edge_keepalived '$site' larch-edge-a"
    [[ "$output" == *"192.168.60.16/32 dev mgmt0 src 192.168.60.10"* ]]
}

@test "rack 2 once both ToRs are provisioned from their edges" {
    site="$(larch_ready)"
    run edge_sh "fleet_edge_ztp_run '$site'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"  larch-edge-a) interface=eno1 address=192.168.61.1/30 tor_address=192.168.61.2 ;;"* ]]
    [[ "$output" == *"  larch-edge-b) interface=eno1 address=192.168.61.5/30 tor_address=192.168.61.6 ;;"* ]]
    run edge_sh "fleet_edge_ztp_dhcp '$site' larch-edge-b"
    [[ "$output" == *"dhcp-host=64:9d:99:d9:81:fe,192.168.61.6,larch-tor-b"* ]]
}

@test "an all-PicOS site's render runs the site checks" {
    larch_with '(.nodes[] | select(.name == "larch-store-a") | .links[] | select(.purpose == "management")) |= (.switch = "larch-tor-a" | .port = 22)' > /dev/null
    run env RACK_SITE=larch-edit "$FLEET_ROOT/fleet.sh" render
    [ "$status" -ne 0 ]
    [[ "$output" == *"it belongs on the opposite one"* ]]
}

@test "one rack switch controller takes every site of its env" {
    run fleet_controller_values "$LARCH"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.watchNamespace' <<<"$output")" = tuist ]
    [ "$(jq -r '.omada.site' <<<"$output")" = ber1 ]
    [ "$(jq -r '.picos.sshKeyItem' <<<"$output")" = "rack-switch-controller picos ssh key" ]
    [ "$(fleet_controller_values "$SITE_FILE")" = "$output" ]
}

@test "two PicOS sites of one env name the same controller items" {
    larch_with '.management.picos.ssh_key_item = "another key"' > /dev/null
    run fleet_controller_values "$LARCH"
    [ "$status" -ne 0 ]
    [[ "$output" == *"name different controller items"* ]]
}

@test "the rack's caches belong to the site rackFleet serves" {
    run edge_sh "fleet_edge_check_rack_caches '$LARCH'"
    [ "$status" -eq 0 ]
}

@test "an edge whose NICs hold fewer descriptors sizes its rings to them" {
    run edge_sh "fleet_edge_path '$LARCH'"
    [ "$status" -eq 0 ]
    [[ "$output" == *'larch-edge-a) vrrp_address=10.255.255.1/29 machines_address=10.20.0.2/24 peer_address=10.255.255.2 ring=2047 uplinks='* ]]
    [[ "$output" == *'ethtool -G "$uplink" rx "$ring" tx "$ring"'* ]]
    run edge_sh "fleet_edge_path '$SITE_FILE'"
    [[ "$output" == *'ethtool -G "$uplink" rx 4096 tx 4096'* ]]
    [[ "$output" != *' ring='* ]]
}

@test "each PicOS ToR with a recorded MAC and a live WAN port sets up its WAN path from zero-touch provisioning" {
    run edge_sh "fleet_picos_wan_paths '$LARCH'"
    [ "$status" -eq 0 ]
    # tor-a holds the carrier on 27 and both edges' legs on 29 and 30; tor-b's
    # MAC is not recorded yet
    [ "$output" = "649d99d9810e 27 29,30" ]
    run edge_sh "fleet_picos_bootstrap '$LARCH'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"wan_vlan='4001 wan'"* ]]
    [[ "$output" == *"wan_paths='649d99d9810e 27 29,30'"* ]]
    [[ "$output" != *"@WAN_"* ]]

    # tor-b's WAN port is a planned spare, so even with its MAC it sets up none
    site="$(larch_ready)"
    run edge_sh "fleet_picos_wan_paths '$site'"
    [ "$output" = "649d99d9810e 27 29,30" ]
    jq '(.devices[] | select(.name == "larch-tor-b") | .ports["27"]) |= del(.status)' "$site" > "$site.new" && mv "$site.new" "$site"
    run edge_sh "fleet_picos_wan_paths '$site'"
    [ "$output" = $'649d99d981fe 27 29,30\n649d99d9810e 27 29,30' ]

    # a site whose edges carry no WAN sets up none
    site="$(larch_with 'del(.management.edge.wan) | .vlans |= map(select(.id != 4001))')"
    run edge_sh "fleet_picos_wan_paths '$site'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run edge_sh "fleet_picos_bootstrap '$site'"
    [[ "$output" == *"wan_paths=''"* ]]
}

# --- the carrier link between alder and larch ---------------------------------

# A copy of a site whose end of the link is live, as it is once the circuit is
# patched in: until then each end is planned and its edges run without it.
live() {
    jq '.management.edge.inter_site.status = "live"' "$1" > "$BATS_TEST_TMPDIR/$(basename "$1")"
    echo "$BATS_TEST_TMPDIR/$(basename "$1")"
}

@test "the link port carries the link VLAN untagged and nothing else, and the edges carry it tagged" {
    run fleet_sh "fleet_render_k8s '$LARCH' larch-tor-b"
    [ "$status" -eq 0 ]
    ports="$(yq -o=json '.spec.config.ports' <<<"$output")"
    port() { jq -c --argjson n "$1" '.[] | select(.port == $n) | [.nativeVlan, .taggedVlans]' <<<"$ports"; }
    [ "$(port 28)" = '[4002,[]]' ]
    [ "$(port 29)" = '[1,[10,20,4000,4001,4002]]' ]
    # A mini never sees it.
    [ "$(port 1)" = '[10,[]]' ]
}

@test "each master holds its end of the link and runs iBGP with BFD to the other's" {
    SITE_FILE="$(live "$SITE_FILE")"; LARCH="$(live "$LARCH")"
    run edge_sh "fleet_edge_keepalived '$SITE_FILE' ber1-edge-b"
    [[ "$output" == *"10.255.254.1/29 dev sites0"* ]]
    run edge_sh "fleet_edge_bgp '$SITE_FILE'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"local 10.255.254.1 as 218377;"* ]]
    [[ "$output" == *"neighbor 10.255.254.4 as 218377;"* ]]
    [[ "$output" == *"bfd on;"* ]]
    # alder accepts larch's machines and WAN address, and nothing of its own
    [[ "$output" == *"if net ~ [ 10.20.0.0/24, 149.6.170.1/32 ] then accept;"* ]]
    [[ "$output" == *$'route 10.10.0.0/24 blackhole;\n  route 149.6.170.31/32 blackhole;'* ]]
    # only what the link taught goes into the node's table
    [[ "$output" == *'export where proto = "link4";'* ]]
    run edge_sh "fleet_edge_bgp '$LARCH'"
    [[ "$output" == *"neighbor 10.255.254.1 as 218377;"* ]]
    [[ "$output" == *"if net ~ [ 10.10.0.0/24, 149.6.170.31/32 ] then accept;"* ]]
}

@test "the other site's machines are reached over the link or not at all" {
    SITE_FILE="$(live "$SITE_FILE")"
    run edge_sh "fleet_edge_path '$SITE_FILE'"
    [ "$status" -eq 0 ]
    bash -n <<<"$output"
    [[ "$output" == *"ip route replace unreachable 10.20.0.0/24 metric 4000 proto static"* ]]
    # not translated onto the link, so the far side sees the mini itself
    [[ "$output" == *'oifname != { "tailscale0", "machines0", "enp87s0", "sites0" } ip saddr 10.10.0.0/24 masquerade'* ]]
    # the storage node reaches larch's WAN address over the link under its own
    [[ "$output" == *'oifname "sites0" ip saddr { 10.10.0.11 } ip daddr 149.6.170.1 snat ip to 149.6.170.31'* ]]
    # a mini reaches larch's segment and nothing else over the link
    [[ "$output" == *'iifname "machines0" oifname "sites0" ip daddr 10.20.0.0/24 accept'* ]]
    [[ "$output" == *$'ip daddr 149.6.170.1 accept\n    iifname "machines0" oifname "sites0" drop'* ]]
    # from the link, only larch's segment reaches only alder's storage node
    [[ "$output" == *'iifname "sites0" oifname "machines0" ip saddr 10.20.0.0/24 ip daddr { 10.10.0.11 } accept'* ]]
    [[ "$output" == *$'iifname "sites0" ip saddr 10.255.254.0/29 tcp dport 179 accept'* ]]
}

@test "a planned link renders nothing on the edges, so landing it rolls no edge" {
    site="$(larch_with 'del(.management.edge.inter_site)')"
    run edge_sh "fleet_edge_path '$site'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"sites0"* ]]
    # the same but for the header naming the file it was rendered from
    without="${output//larch-edit/larch}"
    run edge_sh "fleet_edge_bgp '$site'"
    [[ "$output" != *"link4"* ]]
    # the planned end renders exactly what no link does, on every edge file
    [ "$(jq -r .management.edge.inter_site.status "$LARCH")" = planned ]
    run edge_sh "fleet_edge_path '$LARCH'"
    [ "$output" = "$without" ]
    for render in "fleet_edge_bgp %s" "fleet_edge_keepalived %s larch-edge-a"; do
        a="$(edge_sh "$(printf "$render" "'$LARCH'")")"
        b="$(edge_sh "$(printf "$render" "'$site'")")"
        [ "$a" = "${b//larch-edit/larch}" ]
    done
    # and going live is what puts it there
    run edge_sh "fleet_edge_path '$(live "$LARCH")'"
    [[ "$output" == *"sites0"* ]]
    # a status the edges would not know is refused
    site="$(larch_with '.management.edge.inter_site.status = "patched"')"
    run edge_sh "fleet_edge_check_inter_site '$site'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"status \"patched\" is neither planned nor live"* ]]
}

@test "the link is refused unless exactly one other site shares its prefix with addresses of its own" {
    site="$(larch_with '.management.edge.inter_site.prefix = "10.255.253.0/29" | .management.edge.inter_site.address = "10.255.253.4" | .management.edge.inter_site.members[0].address = "10.255.253.5" | .management.edge.inter_site.members[1].address = "10.255.253.6"')"
    # a copy is not a site, so check the real larch with an edited prefix in its place
    cp "$LARCH" "$BATS_TEST_TMPDIR/larch.orig"
    cp "$site" "$LARCH"
    run edge_sh "fleet_edge_check_inter_site '$LARCH'"
    cp "$BATS_TEST_TMPDIR/larch.orig" "$LARCH"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no other site has a link on 10.255.253.0/29"* ]]

    jq '.management.edge.inter_site.address = "10.255.254.1"' "$BATS_TEST_TMPDIR/larch.orig" > "$LARCH"
    run edge_sh "fleet_edge_check_inter_site '$LARCH'"
    cp "$BATS_TEST_TMPDIR/larch.orig" "$LARCH"
    [ "$status" -ne 0 ]
    [[ "$output" == *"link address 10.255.254.1 of the master edge is already used on the link"* ]]

    site="$(larch_with '.management.edge.inter_site.members |= .[:1]')"
    run edge_sh "fleet_edge_check_inter_site '$site'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"members are larch-edge-a, but the site's edges are larch-edge-a, larch-edge-b"* ]]
}
