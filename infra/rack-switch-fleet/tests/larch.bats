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
    # A mini's port, not yet recorded: on no segment.
    [ "$(port 1)" = '[1,[]]' ]
    # larch-pdu-b's card and larch-edge-b's BMC.
    [ "$(port 23)" = '[20,[]]' ]
    [ "$(port 28)" = '[20,[]]' ]
    # larch-edge-a's leg and the ISL carry the management VLAN tagged, not untagged too.
    [ "$(port 29)" = '[1,[10,20,4000,4001]]' ]
    [ "$(port 25)" = '[1,[10,20,4000,4001]]' ]
    [ "$(port 27)" = '[4001,[]]' ]
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
    site="$(larch_with '(.nodes[] | select(.name == "larch-pdu-a")) |= (.status = "installed" | .mac = "00:20:85:00:00:01")')"
    run edge_sh "fleet_edge_power_devices '$site'"
    [ "$output" = "larch-pdu-a|00:20:85:00:00:01|192.168.60.16" ]
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
