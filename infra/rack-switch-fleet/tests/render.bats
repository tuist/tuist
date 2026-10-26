#!/usr/bin/env bats
# Rendering a switch's configuration from the site definition and the checks
# every render runs: the port map, out-of-band paths, sensors, power, the join
# to the cluster's inventory, the RackSwitch, RackPDU and RackATS objects, and
# reading switch output.

load helpers

# --- terminal noise ----------------------------------------------------------

@test "carriage return erase leaves only the last write" {
    run fleet_sh "printf 'Press any key to continue (Q to quit)\r%76s\r#\n' '' | fleet_normalize"
    [ "${#output}" -eq 0 ]
}

@test "NUL after a carriage return does not survive normalising" {
    # The firmware sends a bare CR as CR NUL. NUL is not whitespace, so an
    # unscrubbed pager line reads as a configuration command that is not there.
    run fleet_sh "printf 'Press any key to continue (Q to quit)\000    #\n' | fleet_normalize"
    [ "${#output}" -eq 0 ]
}

@test "the pager prompt does not swallow the line it erases" {
    run fleet_sh "printf 'Press any key to continue (Q to quit)\000   no controller cloud-based\n' | fleet_normalize"
    [ "$output" = "no controller cloud-based" ]
}

@test "separators, banner and end are not configuration" {
    run fleet_sh "printf '!SX3832\n#\n\nend\n' | fleet_normalize"
    [ "${#output}" -eq 0 ]
}

# --- transcripts -------------------------------------------------------------

@test "the transcript extractor drops the echo and the next prompt" {
    run fleet_sh "fleet_strip_transcript 'show running-config' < '$TRANSCRIPT'"
    [[ "${lines[0]}" == "!SX3832" ]]
    [[ "$output" != *"show running-config"* ]]
    [[ "${lines[-1]}" != *"ber1-tor-b#"* ]]
}

@test "a command that never ran is an error, not an empty configuration" {
    run fleet_sh "fleet_strip_transcript 'show startup-config' < '$TRANSCRIPT'"
    [ "$status" -eq 3 ]
}

@test "NUL does not truncate the record and lose a configuration line" {
    # awk cuts a record at NUL, which silently drops whichever line the pager
    # erased itself in front of. That is why the NUL goes before awk, not after.
    run fleet_sh "fleet_strip_transcript 'show running-config' < '$TRANSCRIPT' | fleet_normalize"
    [[ "$output" == *"no controller cloud-based privacy-policy"* ]]
}

# --- rendering ---------------------------------------------------------------

@test "the rendered configuration matches the live switch" {
    desired="$BATS_TEST_TMPDIR/desired.cfg"
    render_as_captured ber1-tor-b > "$desired"
    run fleet_diff "$desired" "$BODY" rendered live
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 0 ]
}

@test "the admin secret is never rendered" {
    for device in ber1-tor-b ber1-tor-a ber1-mgmt; do
        run fleet_sh "fleet_render '$SITE_FILE' $device"
        [[ "$output" != *"user name"* ]]
    done
}

@test "two switches of the same role differ only where the site says they do" {
    a="$BATS_TEST_TMPDIR/a"; b="$BATS_TEST_TMPDIR/b"
    fleet_render "$SITE_FILE" ber1-tor-a > "$a"
    fleet_render "$SITE_FILE" ber1-tor-b > "$b"
    run bash -c "diff '$a' '$b' | grep '^<'"
    # the hostname, the address, the copper WAN port tor-b has no twin of, the
    # name of the WAN optic's port (tor-b's holds the spare), the name of
    # tor-a's ISL lag on its two members and its port-channel, and ber1-store-a's
    # port on the machines segment, whose pair ber1-store-b is still planned
    [ "${#lines[@]}" -eq 14 ]
    [[ "$output" == *'description "wan cogent"'* ]]
    [[ "$output" == *"switchport pvid 10"* ]]
    [[ "$output" == *'hostname "ber1-tor-a"'* ]]
    [[ "$output" == *"ip address 192.168.0.11"* ]]
    [[ "$output" == *'description "wan copper"'* ]]
    [[ "$output" == *'description "isl ber1-tor-b"'* ]]
}

@test "the committed configs are what the site definition renders" {
    for device in ber1-tor-b ber1-tor-a ber1-mgmt; do
        fleet_render "$SITE_FILE" "$device" > "$BATS_TEST_TMPDIR/$device.cfg"
        run diff -u "$FLEET_ROOT/configs/ber1/$device.cfg" "$BATS_TEST_TMPDIR/$device.cfg"
        [ "$status" -eq 0 ]
    done
}

@test "a model the renderer has never seen is refused" {
    run fleet_model catalyst-9300
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown switch model"* ]]
}

# --- apply ordering ----------------------------------------------------------

@test "the switch with the smallest blast radius goes first" {
    run fleet_apply_order "$SITE_FILE"
    [ "${lines[0]}" = "ber1-tor-b" ]
    [ "${lines[1]}" = "ber1-tor-a" ]
    [ "${lines[2]}" = "ber1-mgmt" ]
}

@test "every device says why it sits where it does" {
    run jq -r '[.devices[] | select((.apply_note | length) < 40)] | length' "$SITE_FILE"
    [ "$output" = "0" ]
}

@test "the order is total, so two switches are never applied together" {
    run jq -r '[.devices[].apply_order] | (length == (unique | length))' "$SITE_FILE"
    [ "$output" = "true" ]
}

@test "a model whose ports were never confirmed is never applied" {
    # Every committed model is confirmed now, so a copy of the tool with one
    # marked otherwise stands in for the next model bought.
    copy="$BATS_TEST_TMPDIR/fleet-copy"
    cp -R "$FLEET_ROOT" "$copy"
    jq '.["tl-sg3452"].verified = false' "$FLEET_ROOT/models.json" > "$copy/models.json"
    jq '(.devices[] | select(.name == "ber1-mgmt")) |= del(.adopted)' "$FLEET_ROOT/sites/ber1.json" > "$copy/sites/ber1.json"
    run env RACK_SITE=ber1 FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" "$copy/fleet.sh" apply ber1-mgmt --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"never been read"* ]]
}

# --- planning ----------------------------------------------------------------

@test "a missing command is planned into its own context" {
    printf '#\ninterface vlan 1\n  ip address 10.0.0.2 255.255.255.0\n  ipv6 enable\nend\n' > "$BATS_TEST_TMPDIR/want"
    printf '#\ninterface vlan 1\n  ip address 10.0.0.2 255.255.255.0\nend\n' > "$BATS_TEST_TMPDIR/have"
    run fleet_sh "fleet_plan_additions '$BATS_TEST_TMPDIR/want' '$BATS_TEST_TMPDIR/have' | fleet_plan_commands"
    [ "${lines[0]}" = "configure" ]
    [ "${lines[1]}" = "interface vlan 1" ]
    [ "${lines[2]}" = "ipv6 enable" ]
    [ "${lines[3]}" = "exit" ]
    [ "${lines[4]}" = "end" ]
}

@test "an unexpected command is reported rather than negated" {
    printf 'interface vlan 1\n  ipv6 enable\nend\n' > "$BATS_TEST_TMPDIR/want"
    printf 'interface vlan 1\n  ipv6 enable\n  ip address 10.0.0.9 255.255.255.0\nend\n' > "$BATS_TEST_TMPDIR/have"
    run fleet_plan_additions "$BATS_TEST_TMPDIR/want" "$BATS_TEST_TMPDIR/have"
    [ "${#output}" -eq 0 ]
    run fleet_plan_removals "$BATS_TEST_TMPDIR/want" "$BATS_TEST_TMPDIR/have"
    [[ "$output" == *"ip address 10.0.0.9 255.255.255.0"* ]]
    [[ "$output" != *"no ip address"* ]]
}

@test "applying a configuration the switch already has plans nothing" {
    desired="$BATS_TEST_TMPDIR/desired.cfg"
    render_as_captured ber1-tor-b > "$desired"
    run fleet_plan_additions "$desired" "$BODY"
    [ "${#output}" -eq 0 ]
}

# --- what the render does not own --------------------------------------------

@test "the local login is not drift" {
    run fleet_sh "printf 'user name tuist privilege admin secret 5 \$1\$abc\n' | fleet_normalize"
    [ "${#output}" -eq 0 ]
}

@test "NTP is not drift while its operand order is unconfirmed" {
    run fleet_sh "printf 'system-time ntp UTC a.example b.example 12 c.example\n' | fleet_normalize"
    [ "${#output}" -eq 0 ]
}

@test "a backup carries the configuration but not the secret" {
    run fleet_sh "fleet_clean < '$BODY'"
    [[ "$output" == *"user name tuist privilege admin secret 5 <redacted"* ]]
    [[ "$output" != *"EXAMPLEHASHNOTREAL"* ]]
    [[ "$output" == *'hostname "ber1-tor-b"'* ]]
}

@test "the committed backup holds no secret" {
    run grep -c '\$1\$' "$FLEET_ROOT/backups/ber1/ber1-tor-b.cfg"
    [ "$output" = "0" ]
}

# --- the wiring record -------------------------------------------------------

@test "a port the model does not have is rejected" {
    device='{"name":"test","model":"sx3832","ports":{"48":{"purpose":"uplink"}}}'
    run fleet_check_ports "$device" "$(fleet_model sx3832)"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not have"* ]]
}

@test "every declared port exists on its switch" {
    for device in ber1-tor-b ber1-tor-a ber1-mgmt; do
        entry="$(fleet_device "$SITE_FILE" "$device")"
        run fleet_check_ports "$entry" "$(fleet_model "$(jq -r '.model' <<<"$entry")")"
        [ "$status" -eq 0 ]
    done
}

@test "the ISL is declared at both ends" {
    run jq -r '[.devices[] | select(.role == "tor") | {a: .name, b: (.ports | to_entries[] | select(.value.purpose == "isl") | .value.peer)}] | unique | sort_by(.a) | map("\(.a)->\(.b)") | join(",")' "$SITE_FILE"
    [ "$output" = "ber1-tor-a->ber1-tor-b,ber1-tor-b->ber1-tor-a" ]
}

# --- the port map, the join between machines and switch ports ----------------

@test "the port map merges node links with the switch's own ports" {
    run fleet_port_map "$SITE_FILE" ber1-tor-b
    [[ "$output" == *"25"*"data"*"ber1-edge-a"*"edge/sfp28-1"* ]]
    [[ "$output" == *"32"*"isl"*"ber1-tor-a"* ]]
}

@test "two things on one port are rejected" {
    site="$BATS_TEST_TMPDIR/clash.json"
    jq '.nodes[0].links[0].port = 32' "$SITE_FILE" > "$site"
    run fleet_check_port_map "$site" ber1-tor-b "$(fleet_model sx3832)"
    [ "$status" -ne 0 ]
    [[ "$output" == *"more than one thing on port"* ]]
}

@test "a node link to a port the switch does not have is rejected" {
    site="$BATS_TEST_TMPDIR/toobig.json"
    jq '.nodes[0].links[0].port = 99' "$SITE_FILE" > "$site"
    run fleet_check_port_map "$site" ber1-tor-b "$(fleet_model sx3832)"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "a node link to a switch this site does not have is rejected" {
    site="$BATS_TEST_TMPDIR/ghost.json"
    jq '.nodes[0].links[0].switch = "us1-tor-a"' "$SITE_FILE" > "$site"
    run fleet_check_nodes "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"us1-tor-a"* ]]
}

@test "a planned link with no port yet is allowed, and not in the port map" {
    run jq -r '[.nodes[].links[] | select(.port == null)] | length' "$SITE_FILE"
    [ "$output" -gt 0 ]
    run fleet_check_nodes "$SITE_FILE"
    [ "$status" -eq 0 ]
}

@test "the model expresses a dual-homed node and a single-homed one" {
    # Data links only: every x86 node also has a management link, and being
    # dual-homed is about which ToRs carry its traffic.
    for edge in ber1-edge-a ber1-edge-b; do
        run jq -r --arg n "$edge" '[.nodes[] | select(.name == $n) | .links[] | select(.purpose == "data") | .switch] | sort | join(",")' "$SITE_FILE"
        [ "$output" = "ber1-tor-a,ber1-tor-b" ]
    done
    # A storage node reaches one ToR, and its pair the other.
    run jq -r '[.nodes[] | select(.name == "ber1-store-a") | .links[] | select(.purpose == "data") | .switch] | join(",")' "$SITE_FILE"
    [ "$output" = "ber1-tor-a" ]
}

@test "the storage pair is split one node per ToR" {
    # Deliberate, and the same split as the ATS chains: losing a ToR must cost
    # one storage node and never both. Tidying them onto one switch would remove
    # the redundancy without looking like it removed anything, so it fails here.
    run jq -r '[.nodes[] | select(.role == "storage") | .links[] | select(.purpose == "data") | .switch] | sort | unique | length' "$SITE_FILE"
    [ "$output" = "2" ]
    run jq -r '[.nodes[] | select(.role == "storage")] | length' "$SITE_FILE"
    [ "$output" = "2" ]
    # exactly one ToR each, so neither is quietly dual-homed onto both
    run jq -r '[.nodes[] | select(.role == "storage") | select(([.links[] | select(.purpose == "data")] | length) != 1)] | length' "$SITE_FILE"
    [ "$output" = "0" ]
}

@test "a node that is not bought yet is planned, not missing" {
    run jq -r '.nodes[] | select(.name == "ber1-store-b") | .status' "$SITE_FILE"
    [ "$output" = "planned" ]
    run fleet_check_nodes "$SITE_FILE"
    [ "$status" -eq 0 ]
}

@test "every node has a status the site understands" {
    run jq -r '[.nodes[] | select(.status != "installed" and .status != "planned")] | length' "$SITE_FILE"
    [ "$output" = "0" ]
}

@test "every node has a role the site defines" {
    run jq -r '[.node_roles | keys[]] as $known | [.nodes[] | select(.role as $r | $known | index($r) | not) | .name] | length' "$SITE_FILE"
    [ "$output" = "0" ]
}

# --- out-of-band paths -------------------------------------------------------

@test "a management link on the NIC without AMT is rejected" {
    # The MS-01's i226-V sits next to the i226-LM, looks the same, and has no
    # AMT. Recording a management link on it is how a node ends up patched into
    # the wrong hole with nothing to show for it until the node needs recovering.
    site="$BATS_TEST_TMPDIR/wrongnic.json"
    jq '(.nodes[] | select(.name == "ber1-edge-a") | .links[] | select(.purpose == "management") | .nic) = "i226-v"' \
        "$SITE_FILE" > "$site"
    run fleet_check_node_interfaces "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"i226-v"* ]]
    [[ "$output" == *"no out-of-band"* ]]
}

@test "a link on an interface the hardware does not have is rejected" {
    site="$BATS_TEST_TMPDIR/ghostnic.json"
    jq '(.nodes[] | select(.name == "ber1-edge-a") | .links[0].nic) = "sfp28-9"' "$SITE_FILE" > "$site"
    run fleet_check_node_interfaces "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"sfp28-9"* ]]
}

@test "every node has exactly one management link, to the management switch" {
    run fleet_check_management_links "$SITE_FILE"
    [ "$status" -eq 0 ]
}

@test "an out-of-band path through a ToR is rejected" {
    # ber1-mgmt uplinks to ber1-edge-a directly and never through a ToR, so a
    # management link landing on a ToR would put out-of-band access behind the
    # thing it exists to recover.
    site="$BATS_TEST_TMPDIR/oobviator.json"
    jq '(.nodes[] | select(.name == "ber1-edge-b") | .links[] | select(.purpose == "management") | .switch) = "ber1-tor-b"' \
        "$SITE_FILE" > "$site"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not ber1-mgmt"* ]]
}

@test "a node with no management link at all is rejected, when its hardware has one" {
    site="$BATS_TEST_TMPDIR/nooob.json"
    jq '(.nodes[] | select(.name == "ber1-edge-b") | .links) |= map(select(.purpose != "management"))' \
        "$SITE_FILE" > "$site"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"expected exactly 1"* ]]
}

@test "every x86 node reaches the management switch on copper" {
    run jq -r '[.nodes[] | select(.hardware == "ms-01") |
        select([.links[] | select(.switch == "ber1-mgmt" and .media == "copper" and .purpose == "management")] | length != 1)] | length' "$SITE_FILE"
    [ "$output" = "0" ]
    run jq -r '[.nodes[] | select(.hardware == "ms-01")] | length' "$SITE_FILE"
    [ "$output" = "4" ]
}

@test "only the edges have a second copper link to the management switch, from their i226-V" {
    run jq -c '[.nodes[] | {name, link: (.links[] | select(.switch == "ber1-mgmt" and .purpose != "management"))} |
        {name, nic: .link.nic, port: .link.port, purpose: .link.purpose}]' "$SITE_FILE"
    [ "$output" = '[{"name":"ber1-edge-a","nic":"i226-v","port":48,"purpose":"edge"},{"name":"ber1-edge-b","nic":"i226-v","port":47,"purpose":"edge"}]' ]
}

@test "the cable schedule has a row for every cable, power included, with the ones still to plug planned" {
    run fleet_cable_schedule "$SITE_FILE"
    [ "$status" -eq 0 ]
    [ "$(grep -c '| ber1-edge-b |' <<<"$output")" -eq 5 ]
    [[ "$output" == *"| ber1-tor-b | 26 | ber1-edge-b | sfp28-1 | dac | data | installed |"* ]]
    [[ "$output" == *"| ber1-tor-a | 26 | ber1-edge-b | sfp28-2 | dac | data | installed |"* ]]
    [[ "$output" == *"| ber1-mgmt | 47 | ber1-edge-b | i226-v | copper | edge | installed |"* ]]
    [[ "$output" == *"| ber1-pdu-b |  | ber1-edge-b | psu | power | power | installed |"* ]]
    [[ "$output" == *"| ber1-ats-3 |  | ber1-pdu-b | inlet | power | power | installed |"* ]]
    [[ "$output" == *"| ber1-pdu-b |  | ber1-tor-b | psu | power | power | installed |"* ]]
    [[ "$output" == *"| ber1-tor-a | 32 | ber1-tor-b |  | dac | isl | installed |"* ]]
    [ "$(diff <(printf '%s\n' "$output") "$FLEET_ROOT/cables/ber1.md")" = "" ]
    # a cable not in yet on an installed node is planned on its own
    jq '(.nodes[] | select(.name == "ber1-edge-b") | .links[] | select(.port == 47)).status = "planned"' \
        "$SITE_FILE" > "$BATS_TEST_TMPDIR/cable.json"
    run fleet_cable_schedule "$BATS_TEST_TMPDIR/cable.json"
    [[ "$output" == *"| ber1-mgmt | 47 | ber1-edge-b | i226-v | copper | edge | planned |"* ]]
    [[ "$output" == *"| ber1-mgmt | 2 | ber1-edge-b | i226-lm | copper | management | installed |"* ]]
}

@test "the cable schedule has a feed cord into each transfer switch inlet" {
    # The cords a person pulls in a chain drill. Without them the schedule had
    # no label for "ber1-ats-3's source 2", and the minis' own cords got pulled.
    run fleet_cable_schedule "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| feed-a |  | ber1-ats-3 | source-1 | power | feed | installed |"* ]]
    [[ "$output" == *"| feed-b |  | ber1-ats-3 | source-2 | power | feed | installed |"* ]]
    [[ "$output" == *"| feed-a |  | ber1-ats-1 | source-1 | power | feed | installed |"* ]]
    [[ "$output" == *"| feed-b |  | ber1-ats-1 | source-2 | power | feed | installed |"* ]]
    [[ "$output" == *"| feed-a |  | ber1-ats-2 | source-1 | power | feed | installed |"* ]]
    [ "$(grep -c '| feed |' <<<"$output")" -eq 6 ]
}

@test "a site with transfer switches names the feed behind each source" {
    run fleet_check_power "$SITE_FILE"
    [ "$status" -eq 0 ]
    local site="$BATS_TEST_TMPDIR/feeds.json"
    jq 'del(.feeds)' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"the site has transfer switches but names no feed for source 1"* ]]
    jq '.feeds = [{source: 1, name: "feed-a"}, {source: 1, name: "feed-c"}, {source: 2, name: "feed-b"}]' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"source 1 has more than one feed"* ]]
}

@test "every node and switch resolves to one transfer switch, and the pairs to different ones" {
    run fleet_check_power "$SITE_FILE"
    [ "$status" -eq 0 ]
    run jq -r '
        ([.nodes[] | select(.hardware == "evmafc20a") | {key: .name, value: .ats}] | from_entries) as $pdus |
        [.nodes[], .devices[] | select(.role == "edge" or .role == "tor") |
          {role, ats: (.ats // $pdus[.pdu])}] | group_by(.role) | map(map(.ats) | unique | length) | join(" ")' "$SITE_FILE"
    [ "$output" = "2 2" ]
}

@test "a pair on one transfer switch is rejected, whichever PDU it goes through" {
    local site="$BATS_TEST_TMPDIR/pair.json"
    jq '(.devices[] | select(.name == "ber1-tor-b")) |= (del(.pdu) + {ats: "ber1-ats-1"})' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-tor-b and ber1-tor-a both resolve to ber1-ats-1"* ]]
    jq '(.nodes[] | select(.name == "ber1-store-b")) |= (del(.pdu) + {ats: "ber1-ats-1"})' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-store-a and ber1-store-b both resolve to ber1-ats-1"* ]]
}

@test "a pair member with no transfer switch is rejected, not skipped" {
    local site="$BATS_TEST_TMPDIR/unfed.json"
    jq '(.nodes[] | select(.name == "ber1-edge-b")) |= del(.pdu)' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-edge-b: one of the edge pair, but names no ats, pdu or feeds"* ]]
    jq '(.nodes[] | select(.name == "ber1-store-b")) |= del(.pdu)' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-store-b: one of the storage pair, but names no ats, pdu or feeds"* ]]
}

@test "a cord goes into one power device, and a PDU hangs off a transfer switch" {
    local site="$BATS_TEST_TMPDIR/cord.json"
    jq '(.nodes[] | select(.name == "ber1-edge-b")).ats = "ber1-ats-2"' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-edge-b: names both ats and pdu"* ]]
    jq '(.nodes[] | select(.name == "ber1-pdu-b")) |= del(.ats)' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-pdu-b: a PDU is fed by a transfer switch"* ]]
    jq '(.nodes[] | select(.name == "ber1-ats-3")).pdu = "ber1-pdu-a"' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-ats-3: a transfer switch takes the facility feeds"* ]]
    jq '(.nodes[] | select(.name == "ber1-kvm-a")).ats = "ber1-pdu-b"' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-kvm-a: ats ber1-pdu-b is not a transfer switch"* ]]
}

@test "two power appliances cannot share a management address" {
    local site="$BATS_TEST_TMPDIR/address.json"
    jq '(.nodes[] | select(.name == "ber1-pdu-b")).mgmt_address = "192.168.0.16"' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-pdu-a and ber1-pdu-b share management address 192.168.0.16"* ]]
}

@test "the things on the management switch that are not machines are modelled" {
    run jq -r '[.nodes[] | select(.role == "console" or .role == "power")] | length' "$SITE_FILE"
    [ "$output" -ge 4 ]
    run jq -r '[.nodes[] | select(.role == "console" or .role == "power") |
        select([.links[].switch] != ["ber1-mgmt"])] | length' "$SITE_FILE"
    [ "$output" = "0" ]
}

# --- hardware with no out-of-band path at all --------------------------------
#
# A Mac mini has no BMC and no AMT, so its recovery is a PDU outlet cycle and
# its console is a crash cart wheeled to the box. There are none in the site
# definition yet and there will eventually be forty-plus, so these pin the rule
# down before the first one lands rather than after.

mini_site() {
    jq '.nodes += [{
          "name": "ber1-runner-a01", "role": "runner", "hardware": "mac-mini",
          "status": "installed", "note": "test fixture",
          "links": [{"switch": "ber1-tor-a", "port": null, "media": "copper", "nic": "en0", "purpose": "data"}]
        }]' "$SITE_FILE" > "$1"
}

@test "a Mac mini needs no management link, because it has no out-of-band path" {
    site="$BATS_TEST_TMPDIR/mini.json"
    mini_site "$site"
    run fleet_check_management_links "$site"
    [ "$status" -eq 0 ]
    run fleet_check_node_interfaces "$site"
    [ "$status" -eq 0 ]
}

@test "giving a Mac mini a management link is rejected, because the cable cannot exist" {
    site="$BATS_TEST_TMPDIR/minioob.json"
    mini_site "$BATS_TEST_TMPDIR/base.json"
    jq '(.nodes[] | select(.name == "ber1-runner-a01") | .links) += [
          {"switch": "ber1-mgmt", "port": null, "media": "copper", "nic": "en0", "purpose": "management"}
        ]' "$BATS_TEST_TMPDIR/base.json" > "$site"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no out-of-band interface"* ]]
}

@test "the hardware that has no out-of-band path says how it is recovered instead" {
    run jq -r '."mac-mini".recovery' "$FLEET_ROOT/node_models.json"
    [ "$output" = "power-cycle" ]
    run jq -r '[."mac-mini".interfaces | to_entries[] | select(.value.out_of_band != null)] | length' "$FLEET_ROOT/node_models.json"
    [ "$output" = "0" ]
}

@test "a Mac mini has one NIC, so it can only land on one ToR" {
    run jq -r '."mac-mini".interfaces | length' "$FLEET_ROOT/node_models.json"
    [ "$output" = "1" ]
}

# --- sensors, which occupy no port at all ------------------------------------

@test "a probe is a node with no links, and that validates" {
    run jq -r '[.nodes[] | select(.role == "environment") | select((.links | length) != 0)] | length' "$SITE_FILE"
    [ "$output" = "0" ]
    run fleet_check_management_links "$SITE_FILE"
    [ "$status" -eq 0 ]
    run fleet_check_node_interfaces "$SITE_FILE"
    [ "$status" -eq 0 ]
}

@test "the probe hardware declares no interfaces, so the absence is the fact" {
    run jq -r '."emp-gen2".interfaces | length' "$FLEET_ROOT/node_models.json"
    [ "$output" = "0" ]
    run jq -r '."emp-gen2".bus' "$FLEET_ROOT/node_models.json"
    [ "$output" = "rs485" ]
}

@test "Modbus address 0 is rejected, because it is never detected" {
    site="$BATS_TEST_TMPDIR/addr0.json"
    jq '(.nodes[] | select(.name == "ber1-env-top") | .attachment.address) = 0' "$SITE_FILE" > "$site"
    run fleet_check_sensor_chains "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"never detected"* ]]
}

@test "two probes sharing a Modbus address are rejected" {
    site="$BATS_TEST_TMPDIR/dupaddr.json"
    jq '(.nodes[] | select(.name == "ber1-env-top") | .attachment.address) = 1' "$SITE_FILE" > "$site"
    run fleet_check_sensor_chains "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"share a Modbus address"* ]]
}

@test "a chain needs exactly one terminated probe, and it is the last" {
    site="$BATS_TEST_TMPDIR/term.json"
    jq '(.nodes[] | select(.name == "ber1-env-exhaust") | .attachment.terminator) = false' "$SITE_FILE" > "$site"
    run fleet_check_sensor_chains "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"expected exactly 1"* ]]

    jq '(.nodes[] | select(.name == "ber1-env-top") | .attachment.terminator) = true' "$SITE_FILE" > "$site"
    run fleet_check_sensor_chains "$site"
    [ "$status" -ne 0 ]

    run jq -r '[.nodes[] | select(.attachment.terminator == true)] | max_by(.attachment.address) | .attachment.address' "$SITE_FILE"
    run jq -r '[.nodes[] | select(.attachment != null)] | (max_by(.attachment.address) | .attachment.terminator)' "$SITE_FILE"
    [ "$output" = "true" ]
}

@test "a probe attached to something that is not a node is rejected" {
    site="$BATS_TEST_TMPDIR/ghosthost.json"
    jq '(.nodes[] | select(.name == "ber1-env-top") | .attachment.host) = "ber1-pdu-z"' "$SITE_FILE" > "$site"
    run fleet_check_sensor_chains "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a node in this site"* ]]
}

# --- the power appliances ----------------------------------------------------

@test "the power gear is Eaton, three transfer switches and two PDUs, all installed" {
    run jq -r '[.nodes[] | select(.hardware == "eats16n")] | length' "$SITE_FILE"
    [ "$output" = "3" ]
    run jq -r '[.nodes[] | select(.hardware == "evmafc20a")] | length' "$SITE_FILE"
    [ "$output" = "2" ]
    run jq -r '[.nodes[] | select(.role == "power" and .status == "installed") | .name] | join(" ")' "$SITE_FILE"
    [ "$output" = "ber1-ats-1 ber1-ats-2 ber1-ats-3 ber1-pdu-a ber1-pdu-b" ]
}

@test "the PDU records the protocol a power driver should target" {
    run jq -r '."evmafc20a".management_protocols[0]' "$FLEET_ROOT/node_models.json"
    [ "$output" = "rest" ]
}

@test "the transfer switches are managed, so they keep a management link" {
    run fleet_check_management_links "$SITE_FILE"
    [ "$status" -eq 0 ]
    run jq -r '[.nodes[] | select(.hardware == "eats16n") |
        select([.links[] | select(.purpose == "management" and .switch == "ber1-mgmt")] | length != 1)] | length' "$SITE_FILE"
    [ "$output" = "0" ]
}

# --- the join to the cluster's own inventory ---------------------------------

mini_referencing() {
    jq --arg h "$2" --arg tor "${3:-ber1-tor-b}" '.nodes += [{
          "name": "ber1-runner-x01", "role": "runner", "hardware": "mac-mini",
          "status": "installed", "rack_host": $h,
          "links": [{"switch": $tor, "port": null, "media": "copper", "nic": "en0", "purpose": "data"}]
        }]' "$SITE_FILE" > "$1"
}

@test "a node may reference a RackHost that exists" {
    site="$BATS_TEST_TMPDIR/ref.json"
    mini_referencing "$site" ber1-runner-b01
    run fleet_check_rack_hosts "$site"
    [ "$status" -eq 0 ]
}

@test "a reference to a RackHost that does not exist is rejected" {
    site="$BATS_TEST_TMPDIR/ghost.json"
    mini_referencing "$site" ber1-ghost-99
    run fleet_check_rack_hosts "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-ghost-99"* ]]
}

@test "a node that references a RackHost may not restate what RackHost owns" {
    # Serial, address, rack position and outlet live in rackFleet.hosts and the
    # controller acts on those. A second copy here is a second chance to
    # disagree, and this side is the one nothing would notice was stale.
    for field in serial address rack power; do
        site="$BATS_TEST_TMPDIR/dup-$field.json"
        mini_referencing "$BATS_TEST_TMPDIR/base-ref.json" ber1-runner-b01
        jq --arg f "$field" '(.nodes[-1] | .[$f]) = "whatever"' "$BATS_TEST_TMPDIR/base-ref.json" > "$site"
        run fleet_check_rack_hosts "$site"
        [ "$status" -ne 0 ]
        [[ "$output" == *"$field"* ]]
    done
}

@test "the site's mini references its RackHost, and that validates" {
    run jq -r '[.nodes[] | select(.rack_host != null) | .rack_host] | join(" ")' "$SITE_FILE"
    [ "$output" = "ber1-runner-b01 ber1-runner-b02 ber1-runner-b03 ber1-runner-b04 ber1-runner-b05 ber1-runner-b06 ber1-runner-b07 ber1-runner-b08 ber1-runner-b09 ber1-runner-b10 ber1-runner-b11 ber1-runner-b12 ber1-runner-b13 ber1-runner-b14 ber1-runner-b15 ber1-runner-b16" ]
    run fleet_check_rack_hosts "$SITE_FILE"
    [ "$status" -eq 0 ]
}

@test "a mini whose outlet and ToR are on different chains is rejected" {
    # The outlet is the RackHost's and the ToR port this file's, so only the
    # join sees both. Crossed, one ATS failure takes the whole fleet: half the
    # minis lose power and the other half their switch.
    site="$BATS_TEST_TMPDIR/crossed.json"
    mini_referencing "$site" ber1-runner-b07 ber1-tor-b
    run fleet_check_rack_hosts "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-runner-x01: its outlet on ber1-pdu-a resolves to ber1-ats-2 but its ToR ber1-tor-b to ber1-ats-3, another chain"* ]]
    values="$BATS_TEST_TMPDIR/values.yaml"
    yq '(.rackFleet.hosts[] | select(.name == "ber1-runner-b02")).power.pdu = "ber1-pdu-a"' "$FLEET_RACK_VALUES" > "$values"
    run fleet_check_rack_hosts "$SITE_FILE" "$values"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-runner-b02: its outlet on ber1-pdu-a resolves to ber1-ats-2 but its ToR ber1-tor-b to ber1-ats-3, another chain"* ]]
}

@test "a chain A mini on ToR A passes, ToR A being on the critical layer" {
    # ber1-tor-a is on ber1-ats-1, which feeds no PDU. It carries the WAN and
    # management for every mini already, so a chain A mini behind it gains no
    # transfer switch whose failure takes the whole fleet.
    site="$BATS_TEST_TMPDIR/chain-a.json"
    mini_referencing "$site" ber1-runner-b07 ber1-tor-a
    run fleet_check_rack_hosts "$site"
    [ "$status" -eq 0 ]
}

@test "a RackHost on a PDU the site does not have is rejected" {
    values="$BATS_TEST_TMPDIR/values.yaml"
    yq '(.rackFleet.hosts[] | select(.name == "ber1-runner-b03")).power.pdu = "ber1-pdu-z"' "$FLEET_RACK_VALUES" > "$values"
    run fleet_check_rack_hosts "$SITE_FILE" "$values"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-runner-b03: RackHost ber1-runner-b03 is on ber1-pdu-z, which is not a PDU in this site"* ]]
}

@test "a mini whose outlet is not on a RackPDU is not held to a chain" {
    values="$BATS_TEST_TMPDIR/values.yaml"
    yq '(.rackFleet.hosts[] | select(.name == "ber1-runner-b01")).power = {"host": "192.0.2.9", "outlet": "0"}' "$FLEET_RACK_VALUES" > "$values"
    run fleet_check_rack_hosts "$SITE_FILE" "$values"
    [ "$status" -eq 0 ]
}

# --- the switches as objects -------------------------------------------------

@test "a switch renders as a RackSwitch whose spec comes from the site definition" {
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$SITE_FILE' ber1-tor-b"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kind: RackSwitch"* ]]
    [[ "$output" == *"name: ber1-tor-b"* ]]
    [[ "$output" == *"managementAddress: 192.168.0.12"* ]]
    [[ "$output" == *"applyOrder: 1"* ]]
    [[ "$output" == *"model: sx3832"* ]]
}

@test "the object names the credential item and never carries the credential" {
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$SITE_FILE' ber1-tor-b"
    [[ "$output" == *"credentialItem:"* ]]
    [[ "$output" != *"secret 5"* ]]
    [[ "$output" != *'$1$'* ]]
}

@test "configRevision is the digest of the configuration that was rendered" {
    site="$BATS_TEST_TMPDIR/rev.json"
    before="$(bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_config_revision '$SITE_FILE' ber1-tor-b")"
    jq '.services.lldp = false' "$SITE_FILE" > "$site"
    after="$(bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_config_revision '$site' ber1-tor-b")"
    [ -n "$before" ]
    [ "$before" != "$after" ]

    # and the object reports the same digest as the config it was rendered beside
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$SITE_FILE' ber1-tor-b | grep configRevision"
    [[ "$output" == *"$before"* ]]
}

@test "the committed objects are what the site definition renders" {
    for device in ber1-tor-b ber1-tor-a ber1-mgmt; do
        bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$SITE_FILE' $device" \
            > "$BATS_TEST_TMPDIR/$device.yaml"
        run diff -u "$FLEET_ROOT/k8s/ber1/$device.yaml" "$BATS_TEST_TMPDIR/$device.yaml"
        [ "$status" -eq 0 ]
    done
}

@test "the object carries the port map, so the cluster sees what is plugged in" {
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$SITE_FILE' ber1-tor-b"
    [[ "$output" == *"port: 25"* ]]
    [[ "$output" == *"peer: ber1-edge-a"* ]]
    [[ "$output" == *"purpose: isl"* ]]
}

@test "a switch with no assigned ports still renders a valid object" {
    site="$BATS_TEST_TMPDIR/unassigned.json"
    jq '(.nodes[].links[] | select(.switch == "ber1-mgmt")).port = null' "$SITE_FILE" > "$site"
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$site' ber1-mgmt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kind: RackSwitch"* ]]
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$site' ber1-mgmt | yq '.spec | has(\"ports\")'"
    [ "$output" = "false" ]
}

@test "the CRD the objects are written against exists and declares a status subresource" {
    crd="$FLEET_ROOT/../helm/tuist/crds/tuist.dev_rackswitches.yaml"
    [ -f "$crd" ]
    run yq -r '.spec.names.kind' "$crd"
    [ "$output" = "RackSwitch" ]
    run yq -r '.spec.versions[0].subresources | has("status")' "$crd"
    [ "$output" = "true" ]
    run yq -r '.spec.versions[0].name' "$crd"
    [ "$output" = "v1alpha1" ]
}

@test "config-mode prompts are recognised, not waited out" {
    # `ber1-tor-b(config)#` and `(config-if)#` are what every command `apply`
    # sends comes back to. Leaving the parenthesised forms out of the prompt
    # pattern meant each one ran its full timeout waiting for a prompt that was
    # already on screen, which made apply either glacial or a reported failure.
    source "$FLEET_ROOT/lib/session.sh"
    for prompt in 'sw#' 'sw>' 'sw(config)#' 'sw(config-if)#' 'sw(config-vlan)#'; do
        [[ "$prompt" =~ [A-Za-z0-9._-]+(\([A-Za-z0-9-]+\))?[#\>][[:space:]]*$ ]] || \
            { echo "did not match: $prompt"; false; }
    done
    [[ "banner text" =~ [A-Za-z0-9._-]+(\([A-Za-z0-9-]+\))?[#\>][[:space:]]*$ ]] && \
        { echo "matched something that is not a prompt"; false; }
    true
}

@test "the transcript extractor stops at a config-mode prompt too" {
    # Through fleet_sh, so the child actually has the function: a bare `bash -c`
    # gave "command not found" and the negative assertion passed on the error
    # message. Assert the success and the content, not just the absence.
    printf 'sw#show running-config\nhostname "x"\nend\nsw(config)#\n' > "$BATS_TEST_TMPDIR/t.txt"
    run fleet_sh "fleet_strip_transcript 'show running-config' < '$BATS_TEST_TMPDIR/t.txt'"
    [ "$status" -eq 0 ]
    [[ "$output" == *'hostname "x"'* ]]
    [[ "$output" != *"(config)#"* ]]
    [[ "$output" != *"command not found"* ]]
}

# --- the env the rack belongs to ----------------------------------------------

@test "the rack's env is its namespace's, by the tuist chart's convention" {
    site="$BATS_TEST_TMPDIR/site.json"
    jq '.kubernetes.namespace = "tuist"' "$SITE_FILE" > "$site"
    run fleet_site_env "$site"
    [ "$status" -eq 0 ]
    [ "$output" = production ]
    jq '.kubernetes.namespace = "tuist-canary"' "$SITE_FILE" > "$site"
    run fleet_site_env "$site"
    [ "$output" = canary ]
    jq '.kubernetes.namespace = "omada"' "$SITE_FILE" > "$site"
    run fleet_site_env "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"names no env"* ]]
}

@test "the render reads the RackHosts from the values of the rack's env" {
    site="$BATS_TEST_TMPDIR/site.json"
    jq '.kubernetes.namespace = "tuist"' "$SITE_FILE" > "$site"
    FLEET_RACK_VALUES="" run fleet_rack_values "$site"
    [ "$status" -eq 0 ]
    [[ "$output" == */helm/tuist/values-managed-production.yaml ]]
    FLEET_RACK_VALUES=/elsewhere.yaml run fleet_rack_values "$site"
    [ "$output" = /elsewhere.yaml ]
}

@test "everything that names the rack's env agrees with its namespace" {
    run fleet_check_env "$SITE_FILE"
    [ "$status" -eq 0 ]
    run "$FLEET_ROOT/fleet.sh" --site ber1 env
    [ "$status" -eq 0 ]
    [ "$output" = "$(fleet_site_env "$SITE_FILE")" ]
}

@test "the rack switch controller and the edge take the rack from the site definition" {
    # The env's other sites are larch alone: not the copies of ber1 other tests
    # run against, each with an Omada controller of its own.
    rm -f "$FLEET_ROOT/sites/ber1-standalone.json"
    run "$FLEET_ROOT/fleet.sh" --site ber1 helm-values rack-switch-controller
    [ "$status" -eq 0 ]
    [ "$(jq -r '.watchNamespace' <<<"$output")" = "$(jq -r '.kubernetes.namespace' "$SITE_FILE")" ]
    [ "$(jq -r '.omada.site' <<<"$output")" = "$(jq -r '.management.controller.site' "$SITE_FILE")" ]
    [ "$(jq -r '.omada.controllerAddress' <<<"$output")" = "$(jq -r '.management.controller.address' "$SITE_FILE")" ]
    [ "$(jq -r '.credentials.omadaApiItem' <<<"$output")" = "$(jq -r '.management.controller.credential_item' "$SITE_FILE")" ]
    [ "$(jq -r '.credentials.deviceAccountItem' <<<"$output")" = "$(jq -r '.management.controller.device_account_item' "$SITE_FILE")" ]
    run "$FLEET_ROOT/fleet.sh" --site ber1 helm-values rack-edge
    [ "$(jq -r '.site' <<<"$output")" = ber1 ]
}

@test "a controller vault, address or tailnet name from another env is refused" {
    site="$BATS_TEST_TMPDIR/site.json"
    env="$(fleet_site_env "$SITE_FILE")"
    jq '.management.controller.vault = "tuist-k8s-elsewhere"' "$SITE_FILE" > "$site"
    run fleet_check_env "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"whose cluster reads tuist-k8s-$env"* ]]
    jq '.management.controller.address = ""' "$SITE_FILE" > "$site"
    run fleet_check_env "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a tailnet address"* ]]
    jq '.management.controller.address = "192.168.0.10"' "$SITE_FILE" > "$site"
    run fleet_check_env "$site"
    [[ "$output" == *"is not a tailnet address"* ]]
    jq '.management.controller.url = "https://omada-elsewhere.example.ts.net:8043"' "$SITE_FILE" > "$site"
    run fleet_check_env "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"names omada-elsewhere.example.ts.net"* ]]
}

@test "a second env declaring the rack's hosts or pools is refused" {
    helm="$BATS_TEST_TMPDIR/helm"
    mkdir -p "$helm"
    cp -R "$FLEET_ROOT/../helm/tuist" "$FLEET_ROOT/../helm/omada" "$helm/"
    env="$(fleet_site_env "$SITE_FILE")"
    run fleet_check_env "$SITE_FILE" "$helm"
    [ "$status" -eq 0 ]
    yq -i '.runnersFleet.pools = [{"name": "ber1", "site": "ber1"}]' "$helm/tuist/values-managed-canary.yaml"
    run fleet_check_env "$SITE_FILE" "$helm"
    [ "$status" -ne 0 ]
    [[ "$output" == *"values-managed-canary.yaml declares ber1's hosts or runner pools, but the rack is in $env"* ]]
    rm "$helm/tuist/values-managed-$env.yaml"
    run fleet_check_env "$SITE_FILE" "$helm"
    [[ "$output" == *"which has no values-managed-$env.yaml"* ]]
}

# --- RackPDU objects ---------------------------------------------------------

@test "a PDU with a recorded MAC takes its address from the edge's DHCP, and one without gets no reservation" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_dhcp "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\ndhcp-host=00:20:85:b8:0e:3e,192.168.0.16,ber1-pdu-a,infinite\n'* ]]
    jq '(.nodes[] | select(.name == "ber1-pdu-a")) |= del(.mac)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nomac.json"
    run fleet_edge_dhcp "$BATS_TEST_TMPDIR/nomac.json"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ber1-pdu-a"* ]]
    # the switch behind the edge keeps its reservation, and an unknown MAC
    # still gets the provisioning pool
    [[ "$output" == *"dhcp-host=a8:29:48:fe:b4:be,192.168.0.13,ber1-mgmt,infinite"* ]]
    [[ "$output" == *"dhcp-range=set:provisioning,192.168.50.100,192.168.50.150"* ]]
    # a planned PDU is not reserved until it is installed
    jq '(.nodes[] | select(.name == "ber1-pdu-b")) |= (.mac = "00:20:85:d7:00:ca" | .status = "planned")' "$SITE_FILE" > "$BATS_TEST_TMPDIR/planned.json"
    run fleet_edge_dhcp "$BATS_TEST_TMPDIR/planned.json"
    [[ "$output" != *"00:20:85:d7:00:ca"* ]]
}

@test "each PDU with a management address is a RackPDU, adopted by the controller once installed" {
    run fleet_pdus "$SITE_FILE"
    [ "$output" = $'ber1-pdu-a\nber1-pdu-b' ]
    run fleet_render_pdu "$SITE_FILE" ber1-pdu-a
    [ "$status" -eq 0 ]
    [ "$(yq 'select(.kind == "RackPDU") | .metadata.name' <<<"$output")" = "ber1-pdu-a" ]
    [ "$(yq 'select(.kind == "RackPDU") | .spec | [.site, .model, .address, .chain, .managedBy] | join(" ")' <<<"$output")" = "ber1 evmafc20a 192.168.0.16 ber1-ats-2 controller" ]
    [ "$(yq 'select(.kind == "RackPDU") | .spec.mac' <<<"$output")" = "00:20:85:b8:0e:3e" ]
    # quoted, or YAML 1.1 reads it as a boolean and the CRD refuses it
    [[ "$output" == *'outletStateOnStartup: "on"'* ]]
    # the object alone: its passwords are derived from the root key, and nothing
    # is pushed to 1Password
    [ "$(yq '.kind' <<<"$output")" = "RackPDU" ]
    [[ "$output" != *"PushSecret"* ]]

    # without a recorded MAC the object says nothing about one
    jq '(.nodes[] | select(.name == "ber1-pdu-a")) |= del(.mac)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nomac.json"
    run fleet_render_pdu "$BATS_TEST_TMPDIR/nomac.json" ber1-pdu-a
    [ "$(yq 'select(.kind == "RackPDU") | .spec | has("mac")' <<<"$output")" = "false" ]

    # a PDU not installed yet is standalone
    jq '(.nodes[] | select(.name == "ber1-pdu-a")) |= (.status = "planned")' "$SITE_FILE" > "$BATS_TEST_TMPDIR/planned.json"
    run fleet_pdus "$BATS_TEST_TMPDIR/planned.json"
    [ "$output" = $'ber1-pdu-a\nber1-pdu-b' ]
    run fleet_render_pdu "$BATS_TEST_TMPDIR/planned.json" ber1-pdu-a
    [ "$(yq 'select(.kind == "RackPDU") | .spec.managedBy' <<<"$output")" = "standalone" ]
    [[ "$output" != *"PushSecret"* ]]
}

@test "render --check notices a RackPDU object that no longer matches the site" {
    cp "$FLEET_ROOT/k8s/ber1/ber1-pdu-b.yaml" "$BATS_TEST_TMPDIR/pdu.yaml"
    sed -i.bak 's/managedBy: controller/managedBy: standalone/' "$FLEET_ROOT/k8s/ber1/ber1-pdu-b.yaml"
    RACK_SITE=ber1 run "$FLEET_ROOT/fleet.sh" render --check
    cp "$BATS_TEST_TMPDIR/pdu.yaml" "$FLEET_ROOT/k8s/ber1/ber1-pdu-b.yaml"
    rm -f "$FLEET_ROOT/k8s/ber1/ber1-pdu-b.yaml.bak"
    [ "$status" -ne 0 ]
    [[ "$output" == *"stale: k8s/ber1/ber1-pdu-b.yaml"* ]]
}

# --- RackATS objects ---------------------------------------------------------

@test "each transfer switch prefers the feed its chain is named for" {
    run jq -r '[.nodes[] | select(.hardware == "eats16n") | "\(.name)=\(.preferred_source)"] | join(" ")' "$SITE_FILE"
    [ "$output" = "ber1-ats-1=1 ber1-ats-2=1 ber1-ats-3=2" ]
    run fleet_check_power "$SITE_FILE"
    [ "$status" -eq 0 ]
}

@test "a transfer switch without a preferred source of 1 or 2 is rejected, and nothing else carries one" {
    local site="$BATS_TEST_TMPDIR/preferred.json"
    jq '(.nodes[] | select(.name == "ber1-ats-3")) |= del(.preferred_source)' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-ats-3: preferred_source is missing"* ]]
    jq '(.nodes[] | select(.name == "ber1-ats-3")).preferred_source = 3' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-ats-3: preferred_source is 3"* ]]
    jq '(.nodes[] | select(.name == "ber1-ats-3")).preferred_source = "2"' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -ne 0 ]
    jq '(.nodes[] | select(.name == "ber1-pdu-b")).preferred_source = 1' "$SITE_FILE" > "$site"
    run fleet_check_power "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-pdu-b: only a transfer switch has a preferred_source"* ]]
}

@test "the transfer switch records the protocol its controller targets" {
    run jq -r '."eats16n".management_protocols[0]' "$FLEET_ROOT/node_models.json"
    [ "$output" = "rest" ]
}

@test "each transfer switch with a management address is a RackATS, adopted by the controller once installed" {
    run fleet_atses "$SITE_FILE"
    [ "$output" = $'ber1-ats-1\nber1-ats-2\nber1-ats-3' ]
    run fleet_render_ats "$SITE_FILE" ber1-ats-3
    [ "$status" -eq 0 ]
    [ "$(yq 'select(.kind == "RackATS") | .metadata.name' <<<"$output")" = "ber1-ats-3" ]
    [ "$(yq 'select(.kind == "RackATS") | .spec | [.site, .model, .address, .managedBy, .preferredSource] | join(" ")' <<<"$output")" = "ber1 eats16n 192.168.0.15 controller 2" ]
    # its recorded MAC, and nothing of a PDU's
    [ "$(yq 'select(.kind == "RackATS") | .spec.mac' <<<"$output")" = "00:20:85:a6:29:4d" ]
    [ "$(yq 'select(.kind == "RackATS") | .spec | (has("chain") or has("outletStateOnStartup"))' <<<"$output")" = "false" ]
    # the object alone, with nothing pushed to 1Password
    [ "$(yq '.kind' <<<"$output")" = "RackATS" ]
    [[ "$output" != *"PushSecret"* ]]
    run fleet_render_ats "$SITE_FILE" ber1-ats-1
    [ "$(yq 'select(.kind == "RackATS") | .spec.preferredSource' <<<"$output")" = "1" ]

    # without a recorded MAC the object carries none
    jq '(.nodes[] | select(.name == "ber1-ats-3")) |= del(.mac)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nomac.json"
    run fleet_render_ats "$BATS_TEST_TMPDIR/nomac.json" ber1-ats-3
    [ "$(yq 'select(.kind == "RackATS") | .spec | has("mac")' <<<"$output")" = "false" ]

    # a transfer switch not installed yet is standalone
    jq '(.nodes[] | select(.name == "ber1-ats-2")) |= (.status = "planned")' "$SITE_FILE" > "$BATS_TEST_TMPDIR/planned.json"
    run fleet_atses "$BATS_TEST_TMPDIR/planned.json"
    [ "$output" = $'ber1-ats-1\nber1-ats-2\nber1-ats-3' ]
    run fleet_render_ats "$BATS_TEST_TMPDIR/planned.json" ber1-ats-2
    [ "$(yq 'select(.kind == "RackATS") | .spec | [.managedBy, .preferredSource] | join(" ")' <<<"$output")" = "standalone 1" ]
    [[ "$output" != *"PushSecret"* ]]
}

@test "a transfer switch with a recorded MAC takes its address from the edge's DHCP, and one without gets no reservation" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_dhcp "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\ndhcp-host=00:20:85:a6:29:61,192.168.0.14,ber1-ats-1,infinite\n'* ]]
    [[ "$output" == *$'\ndhcp-host=00:20:85:a6:29:4d,192.168.0.15,ber1-ats-3,infinite\n'* ]]
    jq '(.nodes[] | select(.hardware == "eats16n")) |= del(.mac)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nomac.json"
    run fleet_edge_dhcp "$BATS_TEST_TMPDIR/nomac.json"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ber1-ats-"* ]]
}

@test "render --check notices a RackATS object that no longer matches the site" {
    cp "$FLEET_ROOT/k8s/ber1/ber1-ats-3.yaml" "$BATS_TEST_TMPDIR/ats.yaml"
    sed -i.bak 's/preferredSource: 2/preferredSource: 1/' "$FLEET_ROOT/k8s/ber1/ber1-ats-3.yaml"
    RACK_SITE=ber1 run "$FLEET_ROOT/fleet.sh" render --check
    cp "$BATS_TEST_TMPDIR/ats.yaml" "$FLEET_ROOT/k8s/ber1/ber1-ats-3.yaml"
    rm -f "$FLEET_ROOT/k8s/ber1/ber1-ats-3.yaml.bak"
    [ "$status" -ne 0 ]
    [[ "$output" == *"stale: k8s/ber1/ber1-ats-3.yaml"* ]]
}

@test "render --check notices a RackPDU or RackATS object the site no longer has, and render removes it" {
    local left="$FLEET_ROOT/k8s/ber1/ber1-pdu-renamed.yaml"
    sed 's/name: ber1-pdu-b$/name: ber1-pdu-renamed/' "$FLEET_ROOT/k8s/ber1/ber1-pdu-b.yaml" > "$left"
    RACK_SITE=ber1 run "$FLEET_ROOT/fleet.sh" render --check
    local check_status="$status" check_output="$output"
    RACK_SITE=ber1 run "$FLEET_ROOT/fleet.sh" render
    local present=0
    [ -e "$left" ] && present=1
    rm -f "$left"
    [ "$check_status" -ne 0 ]
    [[ "$check_output" == *"stale: k8s/ber1/ber1-pdu-renamed.yaml belongs to a power device the site no longer has"* ]]
    [ "$status" -eq 0 ]
    [ "$present" -eq 0 ]
    [[ "$output" == *"removed k8s/ber1/ber1-pdu-renamed.yaml"* ]]
    # a switch's object in the same directory is not the power render's to remove
    [ -e "$FLEET_ROOT/k8s/ber1/ber1-mgmt.yaml" ]
    [ -e "$FLEET_ROOT/k8s/ber1/ber1.yaml" ]
}

# --- RackSite object ---------------------------------------------------------

@test "the site is a RackSite carrying its contracted power steps" {
    run fleet_render_site "$SITE_FILE"
    [ "$status" -eq 0 ]
    [ "$(yq '.kind' <<<"$output")" = "RackSite" ]
    [ "$(yq '.metadata.name' <<<"$output")" = "ber1" ]
    [ "$(yq '[.spec.contractedPower[] | "\(.from)=\(.watts)"] | join(" ")' <<<"$output")" = "2026-10-05=3000 2027-02-05=5000 2027-06-05=8000" ]
    # quoted, or YAML reads it as a timestamp rather than the date string the
    # CRD expects
    [[ "$output" == *'from: "2026-10-05"'* ]]

    # a site without a contract still has its object, with no steps
    jq 'del(.contracted_power)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/nocontract.json"
    run fleet_render_site "$BATS_TEST_TMPDIR/nocontract.json"
    [ "$status" -eq 0 ]
    [ "$(yq '.spec | has("contractedPower")' <<<"$output")" = "false" ]
}

@test "a contracted power step that is not a day and a whole number of watts is rejected" {
    local site="$BATS_TEST_TMPDIR/contract.json"
    jq '.contracted_power[0].from = "05.10.2026"' "$SITE_FILE" > "$site"
    run fleet_render_site "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *'from "05.10.2026" is not a day in the form YYYY-MM-DD'* ]]
    jq '.contracted_power[0].from = "2027-02-30"' "$SITE_FILE" > "$site"
    run fleet_check_contracted_power "$site"
    [ "$status" -ne 0 ]
    jq '.contracted_power[0].watts = "3000"' "$SITE_FILE" > "$site"
    run fleet_check_contracted_power "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *'2026-10-05: watts "3000" is not a whole number of watts above 0'* ]]
    jq '.contracted_power[0].watts = 0' "$SITE_FILE" > "$site"
    run fleet_check_contracted_power "$site"
    [ "$status" -ne 0 ]
    jq '.contracted_power[1].from = "2026-10-05"' "$SITE_FILE" > "$site"
    run fleet_check_contracted_power "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"2026-10-05 has more than one step"* ]]
}

@test "render --check notices a RackSite object that no longer matches the site" {
    cp "$FLEET_ROOT/k8s/ber1/ber1.yaml" "$BATS_TEST_TMPDIR/site.yaml"
    sed -i.bak 's/watts: 3000/watts: 4000/' "$FLEET_ROOT/k8s/ber1/ber1.yaml"
    RACK_SITE=ber1 run "$FLEET_ROOT/fleet.sh" render --check
    cp "$BATS_TEST_TMPDIR/site.yaml" "$FLEET_ROOT/k8s/ber1/ber1.yaml"
    rm -f "$FLEET_ROOT/k8s/ber1/ber1.yaml.bak"
    [ "$status" -ne 0 ]
    [[ "$output" == *"stale: k8s/ber1/ber1.yaml"* ]]
}

@test "the machines segment's addresses, members and machines are checked at render" {
    source "$FLEET_ROOT/lib/edge.sh"
    site="$BATS_TEST_TMPDIR/machines.json"
    jq '.management.edge.machines.members |= map(select(.node != "ber1-edge-b"))' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"machines.members are ber1-edge-a, but the site's edges are ber1-edge-a, ber1-edge-b"* ]]
    jq '.management.edge.machines.members[1].address = "10.10.1.3"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-edge-b's machines address 10.10.1.3 is not in 10.10.0.1/24"* ]]
    jq '.management.edge.machines.members[1].address = "10.10.0.1"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"already the gateway's or another edge's"* ]]
    jq '.management.edge.machines.gateway = "10.10.0.1"' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not an address with its prefix length"* ]]
    jq '(.vlans[] | select(.id == 10)) |= del(.carried_by)' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"VLAN 10 floats an edge address but is not carried_by the edges"* ]]
    jq '(.nodes[] | select(.name == "ber1-runner-b01") | .links[0]) |= del(.mac)' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-runner-b01 has no MAC on its data link"* ]]
    jq '(.nodes[] | select(.name == "ber1-runner-b01")) |= del(.rack_host)' "$SITE_FILE" > "$site"
    run fleet_edge_check "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-runner-b01 is on the machines segment and is neither a RackHost nor a RackLinuxHost"* ]]
    values="$BATS_TEST_TMPDIR/values.yaml"
    yq '(.rackFleet.hosts[] | select(.name == "ber1-runner-b01")).address = "192.168.0.41"' "$FLEET_RACK_VALUES" > "$values"
    run fleet_edge_check_machines "$SITE_FILE" "$values"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-runner-b01's address 192.168.0.41 is not in the machines segment 10.10.0.1/24"* ]]
    yq '(.rackFleet.hosts[] | select(.name == "ber1-runner-b01")).address = "10.10.0.2"' "$FLEET_RACK_VALUES" > "$values"
    run fleet_edge_check_machines "$SITE_FILE" "$values"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ber1-runner-b01's address 10.10.0.2 is already the gateway's, an edge's or another machine's"* ]]
    run fleet_edge_check_machines "$SITE_FILE"
    [ "$status" -eq 0 ]
}

# --- reading show users, from real output on 2026-09-22 ----------------------

@test "the current connection is the newest task, not the first one listed" {
    # Preflight on ber1-tor-b listed tSsh00 (a line recover leaked) and tSsh02
    # (itself), and reported "connection 1" because it read the first match.
    users="$(printf 'tid\tvty\tname\tsock\ttype\n4\t---\ttSsh00\t7\tSSH\n5\t---\ttSsh02\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_current_connection"
    [ "$output" = "02" ]
}

@test "a connection's own line is the newest task, by tid and name" {
    users="$(printf 'tid\tvty\tname\tsock\ttype\n4\t---\ttSsh00\t7\tSSH\n5\t---\ttSsh02\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_own_line"
    [ "$output" = "5 tSsh02" ]
}

@test "recover's leaked line is the one session one saw as its own, while it is still listed" {
    users="$(printf 'tid\tvty\tname\tsock\ttype\n4\t---\ttSsh05\t7\tSSH\n6\t---\ttSsh06\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_leaked_line 4 tSsh05"
    [ "$output" = "4" ]
}

@test "a line opened between the two sessions is never taken for the leaked one" {
    # It could be an operator's own SSH session, and it sits directly below the
    # session that follows, which is where a task-number guess would look.
    users="$(printf 'tid\tvty\tname\tsock\ttype\n5\t---\ttSsh01\t7\tSSH\n6\t---\ttSsh02\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_leaked_line 4 tSsh00"
    [ -z "$output" ]
}

@test "a reused tid under another name is left alone" {
    users="$(printf 'tid\tvty\tname\tsock\ttype\n4\t---\ttSsh01\t7\tSSH\n6\t---\ttSsh02\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_leaked_line 4 tSsh00"
    [ -z "$output" ]
}

@test "the connection asking is never the one cleared" {
    users="$(printf 'tid\tvty\tname\tsock\ttype\n5\t---\ttSsh03\t8\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_leaked_line 5 tSsh03"
    [ -z "$output" ]
}

@test "with no identity from session one, there is nothing to clear" {
    users="$(printf 'tid\tvty\tname\tsock\ttype\n4\t---\ttSsh00\t7\tSSH\n5\t---\ttSsh01\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_leaked_line '' ''"
    [ -z "$output" ]
}

@test "the edge hands every machine on the segment the domain AMT's provisioning certificate is issued under" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_dhcp "$SITE_FILE"
    [ "$status" -eq 0 ]
    # DHCP option 15, which AMT checks against its provisioning certificate
    [[ "$output" == *$'\ndhcp-option=option:domain-name,rack.tuist.dev\n'* ]]
    site="$BATS_TEST_TMPDIR/nodomain.json"
    jq 'del(.management.edge.domain)' "$SITE_FILE" > "$site"
    run fleet_edge_dhcp "$site"
    [ "$status" -eq 0 ]
    [[ "$output" != *"domain-name"* ]]
    jq '.management.edge.domain = "rack.tuist.dev;evil"' "$SITE_FILE" > "$site"
    run fleet_edge_dhcp "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"management.edge.domain"* ]]
}
