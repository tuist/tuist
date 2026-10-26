#!/usr/bin/env bats
# PicOS ToRs: the RackSwitch the rack switch controller writes them from, and
# the zero-touch provisioning their edge serves.

load helpers

controller_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGtoh9Tz1HAy1HdkAXn5W2K8qpmAZdQ3ow2V8L4gBP2m rack-switch-controller"

# The site with a PicOS ToR whose management port is cabled to ber1-edge-a's
# second SFP28 port, as rack 2's ToRs are to their edges' first onboard ports.
site_with_picos_tor() {
    jq --arg key "$controller_key" '
        .devices += [{
            name: "ber1-tor-p", role: "tor", model: "s5860-24xmg",
            mgmt_address: "192.168.61.2", mac: "64:9d:99:d9:81:0e", adopted: true,
            credential_item: "ber1-tor-p admin", console_baud: 115200,
            apply_order: 9, apply_note: "bench",
            feeds: ["feed-a", "feed-b"]
        }]
        | (.nodes[] | select(.name == "ber1-edge-a")) |= (.tor_management = {
            switch: "ber1-tor-p", nic: "sfp28-2", address: "192.168.61.1/30"})
        | .management.picos = {authorized_keys: [$key], ntp: ["162.159.200.1", "162.159.200.123"]}' \
        "$SITE_FILE" > "$FLEET_ROOT/sites/ber1-picos.json"
    echo "$FLEET_ROOT/sites/ber1-picos.json"
}

teardown() { rm -f "$FLEET_ROOT/sites/ber1-picos.json"; }

edge_sh() { bash -c "source '$FLEET_ROOT/lib/config.sh'; source '$FLEET_ROOT/lib/edge.sh'; $1"; }

@test "a PicOS switch renders as a RackSwitch for the picos driver" {
    site="$(site_with_picos_tor)"
    run fleet_sh "fleet_render_k8s '$site' ber1-tor-p"
    [ "$status" -eq 0 ]
    [[ "$output" == *"driver: picos"* ]]
    [[ "$output" == *"managedBy: controller"* ]]
    [[ "$output" == *"mac: 64:9d:99:d9:81:0e"* ]]
    [[ "$output" =~ configRevision:\ [0-9a-f]{16} ]]
}

@test "a PicOS switch's revision follows its configuration" {
    site="$(site_with_picos_tor)"
    before="$(fleet_sh "fleet_render_k8s '$site' ber1-tor-p" | grep configRevision)"
    jq '(.devices[] | select(.name == "ber1-tor-p")).ports = {"5": {purpose: "data", peer: "ber1-mini-05", media: "copper", description: "ber1-mini-05"}}' \
        "$site" > "$site.new" && mv "$site.new" "$site"
    after="$(fleet_sh "fleet_render_k8s '$site' ber1-tor-p" | grep configRevision)"
    [ "$before" != "$after" ]
}

@test "an Omada switch's RackSwitch names no driver" {
    site="$(site_with_picos_tor)"
    run fleet_sh "fleet_render_k8s '$site' ber1-tor-b"
    [ "$status" -eq 0 ]
    [[ "$output" != *"driver:"* ]]
}

@test "a PicOS switch gets a RackSwitch object and no configuration text" {
    site_with_picos_tor > /dev/null
    run env RACK_SITE=ber1-picos "$FLEET_ROOT/fleet.sh" render ber1-tor-p
    [ "$status" -eq 0 ]
    [ -f "$FLEET_ROOT/k8s/ber1-picos/ber1-tor-p.yaml" ]
    [ ! -e "$FLEET_ROOT/configs/ber1-picos/ber1-tor-p.cfg" ]
}

@test "the edge answers DHCP for its ToR alone and serves the bootstrap over TFTP" {
    site="$(site_with_picos_tor)"
    run edge_sh "fleet_edge_ztp_dhcp '$site' ber1-edge-a"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'interface=enp2s0f0np0\nbind-interfaces'* ]]
    [[ "$output" == *"dhcp-range=192.168.61.0,static,255.255.255.252,1h"* ]]
    [[ "$output" == *"dhcp-host=64:9d:99:d9:81:0e,192.168.61.2,ber1-tor-p"* ]]
    [[ "$output" == *"dhcp-ignore=tag:!known"* ]]
    # Options 66 and 67 for ZTP, measured on the bench; the quotes are dnsmasq's
    # in a configuration file, where it strips them.
    [[ "$output" == *"dhcp-option=66,192.168.61.1"* ]]
    [[ "$output" == *'dhcp-option=67,"picos-bootstrap.sh"'* ]]
    [[ "$output" == *"tftp-root=/etc/rack-edge"* ]]
    run edge_sh "fleet_edge_ztp_dhcp '$site' ber1-edge-b"
    [ "$status" -ne 0 ]
}

@test "ztp.sh puts the edge's address on the link and forwards the ToR's NTP alone" {
    site="$(site_with_picos_tor)"
    run edge_sh "fleet_edge_ztp_run '$site'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"  ber1-edge-a) interface=enp2s0f0np0 address=192.168.61.1/30 tor_address=192.168.61.2 ;;"* ]]
    [[ "$output" == *'exec rack-tor-console -address "$tor_address"'* ]]
    [[ "$output" == *'iifname "$interface" udp dport 123 accept'* ]]
    [[ "$output" == *'iifname "$interface" drop'* ]]
    [[ "$output" == *'exec dnsmasq --no-daemon --conf-file="/etc/rack-edge/ztp-$NODE_NAME.conf"'* ]]
    bash -n <<<"$output"
}

@test "the edge holding the link advertises the ToR's address" {
    site="$(site_with_picos_tor)"
    run edge_sh "fleet_edge_routes '$site'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"if ip -4 -o addr show dev enp2s0f0np0 2>/dev/null | grep -qF ' 192.168.61.1/30'; then"* ]]
    [[ "$output" == *'routes="${routes:+$routes,}192.168.61.2/32"'* ]]
}

@test "the bootstrap carries the controller's key and NTP servers and no secret" {
    site="$(site_with_picos_tor)"
    run edge_sh "fleet_picos_bootstrap '$site'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"user='tuist'"* ]]
    [[ "$output" == *"ntp_servers='162.159.200.1 162.159.200.123'"* ]]
    [[ "$output" == *"authorized_keys='$controller_key'"* ]]
    [[ "$output" != *"@USER@"* && "$output" != *"@NTP_SERVERS@"* && "$output" != *"@AUTHORIZED_KEYS@"* ]]
    # Passwords are generated on the switch; none is in the file.
    [[ "$output" != *"PRIVATE KEY"* ]]
    [[ "$output" == *'authentication plain-text-password $(random)"'* ]]
    ! grep -qE 'plain-text-password [A-Za-z0-9]{8,}' <<<"$output"
    bash -n <<<"$output"
}

@test "a bootstrap without the controller's key is refused" {
    site="$(site_with_picos_tor)"
    jq 'del(.management.picos.authorized_keys)' "$site" > "$site.new" && mv "$site.new" "$site"
    run edge_sh "fleet_picos_bootstrap '$site'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"authorized_keys"* ]]
}

@test "a ToR link to a switch that is not PicOS is refused" {
    site="$(site_with_picos_tor)"
    jq '(.nodes[] | select(.name == "ber1-edge-a")).tor_management.switch = "ber1-tor-b"' "$site" > "$site.new" && mv "$site.new" "$site"
    run edge_sh "fleet_edge_check_tor_management '$site'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-tor-b is not a PicOS switch"* ]]
}

@test "a ToR whose address is not the other host on the link is refused" {
    site="$(site_with_picos_tor)"
    jq '(.devices[] | select(.name == "ber1-tor-p")).mgmt_address = "192.168.61.6"' "$site" > "$site.new" && mv "$site.new" "$site"
    run edge_sh "fleet_edge_check_tor_management '$site'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not the other host on ber1-edge-a's link 192.168.61.1/30"* ]]
}

@test "a site with no PicOS ToR renders no ZTP files" {
    run edge_sh "fleet_edge_tor_links '$SITE_FILE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# SFP28 runs at its 25G default, which rack 2's DACs need: the bootstrap
# pins no port speed.
@test "the bootstrap sets no port speed" {
    site="$(site_with_picos_tor)"
    run edge_sh "fleet_picos_bootstrap '$site'"
    [ "$status" -eq 0 ]
    [[ "$output" != *" speed "* ]]
}
