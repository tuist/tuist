#!/usr/bin/env bats
# Tests for the rack switch fleet renderer, differ and session driver.
#
#   bats infra/rack-switch-fleet/tests
#
# The interesting fixture is a real `show running-config` transcript taken off
# ber1-tor-b, pager artefacts and all. Its NUL bytes are written as the two
# characters \0 so the fixture stays reviewable in a diff, and are decoded here.

setup_file() {
    FLEET_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export FLEET_ROOT
    export FIXTURE="$BATS_TEST_DIRNAME/fixtures/ber1-tor-b-running-config.txt"

    export TRANSCRIPT="$BATS_FILE_TMPDIR/transcript.txt"
    perl -pe 's/\\0/\x00/g' "$FIXTURE" > "$TRANSCRIPT"

    # The config body alone, cut with sed so the extractor under test is not
    # used to build its own input.
    export BODY="$BATS_FILE_TMPDIR/body.txt"
    sed -n '/#show running-config$/,$p' "$TRANSCRIPT" | sed '1d;$d' > "$BODY"
}

setup() {
    source "$FLEET_ROOT/lib/config.sh"
    SITE_FILE="$(fleet_site_file ber1)"
}

# A copy of the site with ber1-mgmt's MAC removed, for the paths that handle a
# switch whose MAC nobody has recorded yet. Tools resolve a site by name under
# sites/, so the copy has to live there; teardown removes it.
site_without_mgmt_mac() {
    jq '(.devices[] | select(.name == "ber1-mgmt")) |= del(.mac)' "$SITE_FILE" \
        > "$FLEET_ROOT/sites/ber1-nomac.json"
}

teardown() {
    rm -f "$FLEET_ROOT/sites/ber1-nomac.json"
}

# A subshell does not inherit the sourced library, so pipelines under `run` get
# it back this way.
fleet_sh() { bash -c "source '$FLEET_ROOT/lib/config.sh'; $1"; }

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
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
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
    [ "${#lines[@]}" -eq 2 ]
    [[ "$output" == *'hostname "ber1-tor-a"'* ]]
    [[ "$output" == *"ip address 192.168.0.11"* ]]
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
    run "$FLEET_ROOT/fleet.sh" apply ber1-mgmt --dry-run
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
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
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
    run jq -r '[.devices[] | select(.role == "tor") | {a: .name, b: (.ports | to_entries[] | select(.value.purpose == "isl") | .value.peer)}] | sort_by(.a) | map("\(.a)->\(.b)") | join(",")' "$SITE_FILE"
    [ "$output" = "ber1-tor-a->ber1-tor-b,ber1-tor-b->ber1-tor-a" ]
}

# --- the session driver, against a fake switch -------------------------------

@test "the session driver reads a config back through the pager and logs out" {
    stub="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub"
    cat > "$stub/ssh" <<STUB
#!/usr/bin/env bash
# A switch that echoes like the real one: prompt, echoed command, output. It
# waits before answering, because a switch that replies within one read
# interval hides a drain that gives up on its first timeout.
sleep 1
printf 'ber1-tor-b>'
while IFS= read -r line; do
    sleep 1
    line="\${line%\$'\r'}"
    printf '%s\r\n' "\$line"
    case "\$line" in
        logout) exit 0;;
        "show running-config") cat "$BODY";;
    esac
    printf '\r\nber1-tor-b#'
done
STUB
    chmod +x "$stub/ssh"

    source "$FLEET_ROOT/lib/session.sh"
    PATH="$stub:$PATH"
    run bash -c "
        set -eu
        export PATH="$stub:\$PATH"
        source '$FLEET_ROOT/lib/config.sh'
        source '$FLEET_ROOT/lib/session.sh'
        switch_open 192.0.2.1 tuist /dev/null
        switch_run 'show running-config'
        printf '%s\n' \"\$SWITCH_OUTPUT\" > '$BATS_TEST_TMPDIR/raw'
        fleet_strip_transcript 'show running-config' < '$BATS_TEST_TMPDIR/raw' > '$BATS_TEST_TMPDIR/live'
        switch_close
    "
    [ "$status" -eq 0 ]

    desired="$BATS_TEST_TMPDIR/desired.cfg"
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
    run fleet_diff "$desired" "$BATS_TEST_TMPDIR/live" rendered live
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 0 ]
}

@test "a connection that fails fast reports why, instead of an unbound variable" {
    # Bash deletes the coprocess array as soon as the coprocess is reaped, so a
    # dead ssh turns every ${SWITCH[0]} into an unbound variable under set -u.
    stub="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub"
    cat > "$stub/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh: connect to host 192.0.2.1 port 22: Connection refused" >&2
exit 255
STUB
    chmod +x "$stub/ssh"

    run bash -c "
        set -euo pipefail
        export PATH=\"$stub:\$PATH\"
        source '$FLEET_ROOT/lib/session.sh'
        switch_open 192.0.2.1 tuist /dev/null
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"accepted no session"* ]]
    [[ "$output" == *"Connection refused"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "a session that dies mid-command fails loudly instead of on SIGPIPE" {
    # Writing to a coprocess whose ssh has exited raises SIGPIPE, and a shell
    # killed by SIGPIPE never runs its EXIT trap. The logout is then skipped,
    # the switch keeps the session, and enough of those wedge its SSH daemon.
    stub="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub"
    cat > "$stub/ssh" <<'STUB'
#!/usr/bin/env bash
sleep 0.5
printf 'ber1-tor-b>'
IFS= read -r _enable
sleep 0.3
printf '\r\nber1-tor-b#'
echo "Connection to 192.0.2.1 closed by remote host." >&2
exit 255
STUB
    chmod +x "$stub/ssh"

    run bash -c "
        set -euo pipefail
        export PATH=\"$stub:\$PATH\"
        source '$FLEET_ROOT/lib/session.sh'
        trap switch_close EXIT
        switch_open 192.0.2.1 tuist /dev/null
        switch_run 'copy startup-config tftp ip-address 192.0.2.9 filename x.cfg'
    "
    [ "$status" -ne 0 ]
    [ "$status" -ne 141 ]
    # Caught at switch_open now, because `switch_run enable` propagates its
    # failure rather than being swallowed. Either message is the session ending;
    # what matters is that it is reported and is not a signal death.
    [[ "$output" == *"closed the session"* || "$output" == *"accepted no session"* \
       || "$output" == *"ended the session"* ]]
}

# --- the port map, the join between machines and switch ports ----------------

@test "the port map merges node links with the switch's own ports" {
    run fleet_port_map "$SITE_FILE" ber1-tor-b
    [[ "$output" == *"25"*"data"*"ber1-edge"*"edge/sfp28-1"* ]]
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
    run jq -r '[.nodes[] | select(.name == "ber1-edge") | .links[] | select(.purpose == "data") | .switch] | sort | join(",")' "$SITE_FILE"
    [ "$output" = "ber1-tor-a,ber1-tor-b" ]
    # ber1-svc reaches one ToR, which is the rack risk its note records. Adding
    # the second link is a data edit.
    run jq -r '[.nodes[] | select(.name == "ber1-svc") | .links[] | select(.purpose == "data") | .switch] | join(",")' "$SITE_FILE"
    [ "$output" = "ber1-tor-b" ]
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
    jq '(.nodes[] | select(.name == "ber1-edge") | .links[] | select(.purpose == "management") | .nic) = "i226-v"' \
        "$SITE_FILE" > "$site"
    run fleet_check_node_interfaces "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"i226-v"* ]]
    [[ "$output" == *"no out-of-band"* ]]
}

@test "a link on an interface the hardware does not have is rejected" {
    site="$BATS_TEST_TMPDIR/ghostnic.json"
    jq '(.nodes[] | select(.name == "ber1-edge") | .links[0].nic) = "sfp28-9"' "$SITE_FILE" > "$site"
    run fleet_check_node_interfaces "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"sfp28-9"* ]]
}

@test "every node has exactly one management link, to the management switch" {
    run fleet_check_management_links "$SITE_FILE"
    [ "$status" -eq 0 ]
}

@test "an out-of-band path through a ToR is rejected" {
    # ber1-mgmt uplinks to ber1-edge directly and never through a ToR, so a
    # management link landing on a ToR would put out-of-band access behind the
    # thing it exists to recover.
    site="$BATS_TEST_TMPDIR/oobviator.json"
    jq '(.nodes[] | select(.name == "ber1-svc") | .links[] | select(.purpose == "management") | .switch) = "ber1-tor-b"' \
        "$SITE_FILE" > "$site"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not ber1-mgmt"* ]]
}

@test "a node with no management link at all is rejected, when its hardware has one" {
    site="$BATS_TEST_TMPDIR/nooob.json"
    jq '(.nodes[] | select(.name == "ber1-svc") | .links) |= map(select(.purpose != "management"))' \
        "$SITE_FILE" > "$site"
    run fleet_check_management_links "$site"
    [ "$status" -ne 0 ]
    [[ "$output" == *"expected exactly 1"* ]]
}

@test "every x86 node reaches the management switch on copper" {
    run jq -r '[.nodes[] | select(.hardware == "ms-01") |
        select([.links[] | select(.switch == "ber1-mgmt" and .media == "copper")] | length != 1)] | length' "$SITE_FILE"
    [ "$output" = "0" ]
    run jq -r '[.nodes[] | select(.hardware == "ms-01")] | length' "$SITE_FILE"
    [ "$output" = "4" ]
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

@test "the power gear is Eaton, three transfer switches and two PDUs, all planned" {
    run jq -r '[.nodes[] | select(.hardware == "eats16n")] | length' "$SITE_FILE"
    [ "$output" = "3" ]
    run jq -r '[.nodes[] | select(.hardware == "evmafc20a")] | length' "$SITE_FILE"
    [ "$output" = "2" ]
    run jq -r '[.nodes[] | select(.role == "power") | select(.status != "planned")] | length' "$SITE_FILE"
    [ "$output" = "0" ]
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

# --- the file that would be pushed -------------------------------------------
#
# The TFTP export turned out to be text, so a whole-config replace is possible.
# The fixture is a real export off ber1-tor-b with the hash replaced.

export_fixture() { echo "$FLEET_ROOT/tests/fixtures/ber1-tor-b-tftp-export.cfg"; }

@test "the exported file and the render describe the same configuration" {
    desired="$BATS_TEST_TMPDIR/desired.cfg"
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
    run fleet_diff "$desired" "$(export_fixture)" rendered exported
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 0 ]
}

@test "pushing the render alone would delete the login, so the merge carries it" {
    desired="$BATS_TEST_TMPDIR/desired.cfg"
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
    run grep -c '^user name ' "$desired"
    [ "$output" = "0" ]

    merged="$BATS_TEST_TMPDIR/merged.cfg"
    fleet_merge_unmanaged "$(export_fixture)" "$desired" > "$merged"
    run grep -c '^user name tuist ' "$merged"
    [ "$output" = "1" ]
    run grep -c '^system-time ntp ' "$merged"
    [ "$output" = "1" ]
}

@test "the merge loses nothing the switch is holding" {
    desired="$BATS_TEST_TMPDIR/desired.cfg"
    merged="$BATS_TEST_TMPDIR/merged.cfg"
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
    fleet_merge_unmanaged "$(export_fixture)" "$desired" > "$merged"
    run bash -c "diff <(grep -vE '^!|^[[:space:]]*#?[[:space:]]*\$' '$(export_fixture)') \
                      <(grep -vE '^!|^[[:space:]]*#?[[:space:]]*\$' '$merged') | grep '^<' | wc -l | tr -d ' '"
    [ "$output" = "0" ]
}

@test "an unmanaged line is put back where the device had it, not at a fixed offset" {
    # Derived from the current config rather than hard-coded, so a firmware that
    # cares about ordering keeps working without this code knowing the order.
    current="$BATS_TEST_TMPDIR/current.cfg"
    printf 'lldp\nsystem-time ntp UTC a b 12\nno system-time dst\nspanning-tree\n' > "$current"
    printf 'lldp\nno system-time dst\nspanning-tree\nend\n' > "$BATS_TEST_TMPDIR/want.cfg"
    run fleet_merge_unmanaged "$current" "$BATS_TEST_TMPDIR/want.cfg"
    [ "${lines[0]}" = "lldp" ]
    [ "${lines[1]}" = "system-time ntp UTC a b 12" ]
    [ "${lines[2]}" = "no system-time dst" ]
}

@test "an unmanaged line with nothing after it still survives the merge" {
    current="$BATS_TEST_TMPDIR/tail.cfg"
    printf 'lldp\nuser name tuist privilege admin secret 5 $1$x\n' > "$current"
    printf 'lldp\nend\n' > "$BATS_TEST_TMPDIR/want2.cfg"
    run fleet_merge_unmanaged "$current" "$BATS_TEST_TMPDIR/want2.cfg"
    [[ "$output" == *"user name tuist"* ]]
    [ "${lines[-1]}" = "end" ]
}

@test "the device file encoding is CRLF with one trailing NUL" {
    printf 'hostname "x"\nend\n' > "$BATS_TEST_TMPDIR/plain.cfg"
    fleet_device_file < "$BATS_TEST_TMPDIR/plain.cfg" > "$BATS_TEST_TMPDIR/dev.cfg"
    run bash -c "od -c '$BATS_TEST_TMPDIR/dev.cfg' | tr -s ' '"
    [[ "$output" == *'\r \n'* ]]
    run bash -c "tail -c1 '$BATS_TEST_TMPDIR/dev.cfg' | od -An -c | tr -d ' '"
    [ "$output" = '\0' ]
}

# --- replacing a whole configuration -----------------------------------------

fake_switch_bin() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/sudo" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -v) exit 0;;
  launchctl) exit 0;;
  *) exec "$@";;
esac
STUB
    # `route` and `ipconfig` are how replace works out which local address to
    # serve TFTP from. Unstubbed, these tests only pass on a machine that has a
    # route to the rack, which is not a property a test may depend on.
    cat > "$dir/route" <<'STUB'
#!/usr/bin/env bash
echo "   interface: lo0"
STUB
    cat > "$dir/ipconfig" <<'STUB'
#!/usr/bin/env bash
echo "127.0.0.1"
STUB
    chmod +x "$dir/route" "$dir/ipconfig"
    cat > "$dir/ssh" <<'STUB'
#!/usr/bin/env bash
sleep 0.4
printf 'ber1-tor-b>'
while IFS= read -r line; do
    line="${line%$'\r'}"
    sleep 0.2
    printf '%s\r\n' "$line"
    case "$line" in
        logout) exit 0;;
        "copy startup-config tftp"*)
            cp "$FAKE_CURRENT" "$FAKE_TFTP/ber1-tor-b-current.cfg"
            printf ' Backup user config file OK.\r\n';;
        "copy tftp startup-config"*)
            cp "$FAKE_TFTP/ber1-tor-b-desired.cfg" "$FAKE_PUSHED"
            printf ' Load user config file OK.\r\n';;
        reboot) printf ' Continue? (Y/N):'; continue;;
        Y) echo CONFIRMED >> "$FAKE_LOG"; exit 0;;
    esac
    printf '\r\nber1-tor-b#'
done
STUB
    chmod +x "$dir/sudo" "$dir/ssh"
}

@test "a reboot is never confirmed unless the caller says to" {
    # Anything that asks "(Y/N)" and was not run through switch_run_confirm waits
    # out its timeout instead. Rebooting a switch is not a default.
    stub="$BATS_TEST_TMPDIR/bin"
    fake_switch_bin "$stub"
    log="$BATS_TEST_TMPDIR/confirm.log"
    : > "$log"
    run bash -c "
        set -uo pipefail
        export PATH=\"$stub:\$PATH\" FAKE_LOG='$log'
        source '$FLEET_ROOT/lib/session.sh'
        trap switch_close EXIT
        switch_open 192.0.2.1 tuist /dev/null
        switch_run reboot 5 || true
    "
    run cat "$log"
    [ "${#output}" -eq 0 ]
}

@test "switch_run_confirm answers the prompt it was given an answer for" {
    stub="$BATS_TEST_TMPDIR/bin"
    fake_switch_bin "$stub"
    log="$BATS_TEST_TMPDIR/confirm.log"
    : > "$log"
    run bash -c "
        set -uo pipefail
        export PATH=\"$stub:\$PATH\" FAKE_LOG='$log'
        source '$FLEET_ROOT/lib/session.sh'
        trap switch_close EXIT
        switch_open 192.0.2.1 tuist /dev/null
        switch_run_confirm reboot Y 15 || true
    "
    run cat "$log"
    [ "$output" = "CONFIRMED" ]
}

@test "replace pushes a file that keeps the login and carries the change" {
    # route, ipconfig and sudo are all stubbed, so this needs neither macOS nor
    # a route to the rack.
    stub="$BATS_TEST_TMPDIR/bin"
    fake_switch_bin "$stub"
    root="$BATS_TEST_TMPDIR/tftp"; mkdir -p "$root"
    current="$BATS_TEST_TMPDIR/current.cfg"
    grep -v '^!' "$(export_fixture)" > "$current"
    pushed="$BATS_TEST_TMPDIR/pushed.cfg"

    # a real change, so the diff is not empty
    site="$BATS_TEST_TMPDIR/sites/ber1.json"
    mkdir -p "$BATS_TEST_TMPDIR/sites"
    jq '.services.lldp = false' "$SITE_FILE" > "$site"

    run env PATH="$stub:$PATH" TFTP_ROOT="$root" FAKE_TFTP="$root" \
        FAKE_CURRENT="$current" FAKE_PUSHED="$pushed" FLEET_ROOT="$FLEET_ROOT" \
        bash -c "
            cp '$site' '$FLEET_ROOT/sites/ber1-replacetest.json'
            '$FLEET_ROOT/fleet.sh' --site ber1-replacetest replace ber1-tor-b --yes --skip-order-check
            status=\$?
            rm -f '$FLEET_ROOT/sites/ber1-replacetest.json'
            exit \$status
        "
    [ "$status" -eq 0 ]
    [[ "$output" == *"startup config replaced"* ]]

    run grep -c '^user name tuist ' "$pushed"
    [ "$output" = "1" ]
    run bash -c "tr -d '\r\000' < '$pushed' | grep -c '^no lldp$'"
    [ "$output" = "1" ]
    run bash -c "tail -c1 '$pushed' | od -An -c | tr -d ' '"
    [ "$output" = '\0' ]
}

@test "replace refuses to push a file with no login in it" {
    stub="$BATS_TEST_TMPDIR/bin"
    fake_switch_bin "$stub"
    root="$BATS_TEST_TMPDIR/tftp2"; mkdir -p "$root"
    current="$BATS_TEST_TMPDIR/nologin.cfg"
    grep -v '^!' "$(export_fixture)" | grep -v '^user name ' > "$current"
    pushed="$BATS_TEST_TMPDIR/pushed2.cfg"

    run env PATH="$stub:$PATH" TFTP_ROOT="$root" FAKE_TFTP="$root" \
        FAKE_CURRENT="$current" FAKE_PUSHED="$pushed" \
        "$FLEET_ROOT/fleet.sh" replace ber1-tor-b --yes --skip-order-check
    [ "$status" -ne 0 ]
    [[ "$output" == *"no login in it"* ]]
    [ ! -f "$pushed" ]
}

@test "replace names every line it would delete" {
    # The unmanaged list is evidence from one switch. A line only another device
    # has, that the render does not model, must show up here rather than
    # disappear on the next reboot.
    current="$BATS_TEST_TMPDIR/extra.cfg"
    grep -v '^!' "$(export_fixture)" > "$current"
    printf 'radius-server host 10.0.0.5 key secret\n' >> "$current"
    desired="$BATS_TEST_TMPDIR/desired2.cfg"
    merged="$BATS_TEST_TMPDIR/merged2.cfg"
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
    fleet_merge_unmanaged "$current" "$desired" > "$merged"

    run fleet_removed_lines "$current" "$merged"
    [[ "$output" == *"radius-server host 10.0.0.5"* ]]
}

@test "nothing is reported as lost when the switch already matches" {
    current="$BATS_TEST_TMPDIR/same.cfg"
    grep -v '^!' "$(export_fixture)" > "$current"
    desired="$BATS_TEST_TMPDIR/desired3.cfg"
    merged="$BATS_TEST_TMPDIR/merged3.cfg"
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
    fleet_merge_unmanaged "$current" "$desired" > "$merged"
    run fleet_removed_lines "$current" "$merged"
    [ "${#output}" -eq 0 ]
}

@test "the unmanaged list has one definition, so the two awk passes cannot disagree" {
    run grep -c 'user name' "$FLEET_ROOT/lib/merge.awk"
    [ "$output" = "0" ]
    run bash -c "grep -c 'system-time ntp' '$FLEET_ROOT/lib/normalize.awk'"
    [ "$output" = "0" ]
    [ -n "$FLEET_UNMANAGED" ]
}

@test "a removal the render asked for is separated from one it says nothing about" {
    # Merging the two makes the dangerous one quieter the more the fleet uses
    # deliberate removals, which is the shape that trains people past the prompt.
    current="$BATS_TEST_TMPDIR/mixed.cfg"
    grep -v '^!' "$(export_fixture)" > "$current"
    printf 'radius-server host 10.0.0.5 key x\n' >> "$current"

    desired="$BATS_TEST_TMPDIR/mixed-desired.cfg"
    merged="$BATS_TEST_TMPDIR/mixed-merged.cfg"
    fleet_render "$SITE_FILE" ber1-tor-b | sed 's/^lldp$/no lldp/' > "$desired"
    fleet_merge_unmanaged "$current" "$desired" > "$merged"

    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_removed_lines '$current' '$merged' | grep '^declared' | cut -f3"
    [ "$output" = "lldp" ]
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_removed_lines '$current' '$merged' | grep '^undeclared' | cut -f3"
    [ "$output" = "radius-server host 10.0.0.5 key x" ]
}


@test "a file with no login is refused, and one with a login is not" {
    # The guard of last resort, tested on its own: if the merge ever fails to
    # carry the account across, pushing the result locks everyone out of the
    # switch. Runs everywhere, unlike the TFTP path that calls it.
    with="$BATS_TEST_TMPDIR/with-login.cfg"
    without="$BATS_TEST_TMPDIR/without-login.cfg"
    grep -v '^!' "$(export_fixture)" > "$with"
    grep -v '^!' "$(export_fixture)" | grep -v '^user name ' > "$without"

    run fleet_has_login "$with"
    [ "$status" -eq 0 ]
    run fleet_has_login "$without"
    [ "$status" -ne 0 ]
}

@test "the merge of a render into a real export always yields a file with a login" {
    desired="$BATS_TEST_TMPDIR/d.cfg"
    merged="$BATS_TEST_TMPDIR/m.cfg"
    current="$BATS_TEST_TMPDIR/c.cfg"
    grep -v '^!' "$(export_fixture)" > "$current"
    fleet_render "$SITE_FILE" ber1-tor-b > "$desired"
    fleet_merge_unmanaged "$current" "$desired" > "$merged"
    run fleet_has_login "$merged"
    [ "$status" -eq 0 ]
}


@test "a removal is reported against the interface it happens on" {
    # Flattening (context, command) into bare commands made `spanning-tree`
    # under one interface indistinguishable from the same line under another,
    # so dropping it from a single port reported nothing at all.
    current="$BATS_TEST_TMPDIR/ports-before.cfg"
    merged="$BATS_TEST_TMPDIR/ports-after.cfg"
    printf 'interface ten-gigabitEthernet 1/0/5\n  spanning-tree\n#\ninterface ten-gigabitEthernet 1/0/6\n  spanning-tree\n#\nend\n' > "$current"
    printf 'interface ten-gigabitEthernet 1/0/5\n#\ninterface ten-gigabitEthernet 1/0/6\n  spanning-tree\n#\nend\n' > "$merged"

    run fleet_removed_lines "$current" "$merged"
    [ "${#output}" -gt 0 ]
    [[ "$output" == *"undeclared"* ]]
    [[ "$output" == *"1/0/5"* ]]
    [[ "$output" != *"1/0/6"* ]]
}

@test "a command still present elsewhere is not reported as removed" {
    current="$BATS_TEST_TMPDIR/same-before.cfg"
    merged="$BATS_TEST_TMPDIR/same-after.cfg"
    printf 'interface ten-gigabitEthernet 1/0/5\n  spanning-tree\n#\nend\n' > "$current"
    cp "$current" "$merged"
    run fleet_removed_lines "$current" "$merged"
    [ "${#output}" -eq 0 ]
}

# --- the join to the cluster's own inventory ---------------------------------

mini_referencing() {
    jq --arg h "$2" '.nodes += [{
          "name": "ber1-runner-a01", "role": "runner", "hardware": "mac-mini",
          "status": "installed", "rack_host": $h,
          "links": [{"switch": "ber1-tor-a", "port": null, "media": "copper", "nic": "en0", "purpose": "data"}]
        }]' "$SITE_FILE" > "$1"
}

@test "a node may reference a RackHost that exists" {
    site="$BATS_TEST_TMPDIR/ref.json"
    mini_referencing "$site" ber1-proto-01
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
        mini_referencing "$BATS_TEST_TMPDIR/base-ref.json" ber1-proto-01
        jq --arg f "$field" '(.nodes[-1] | .[$f]) = "whatever"' "$BATS_TEST_TMPDIR/base-ref.json" > "$site"
        run fleet_check_rack_hosts "$site"
        [ "$status" -ne 0 ]
        [[ "$output" == *"$field"* ]]
    done
}

@test "nothing in the site definition references a RackHost yet, and that validates" {
    run jq -r '[.nodes[] | select(.rack_host != null)] | length' "$SITE_FILE"
    [ "$output" = "0" ]
    run fleet_check_rack_hosts "$SITE_FILE"
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
    [[ "$output" == *"peer: ber1-edge"* ]]
    [[ "$output" == *"purpose: isl"* ]]
}

@test "a switch with no assigned ports still renders a valid object" {
    run bash -c "source '$FLEET_ROOT/lib/config.sh'; fleet_render_k8s '$SITE_FILE' ber1-mgmt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kind: RackSwitch"* ]]
    [[ "$output" != *"ports:"* ]]
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

# --- the lock, and what it has to survive ------------------------------------

@test "a real command refuses a stale lock and leaves it alone" {
    # Through fleet.sh, so the lock path is actually exercised rather than a
    # reimplementation of it. `replace --dry-run` takes the lock before it does
    # anything else.
    lock="$BATS_TEST_TMPDIR/rack-fleet-ber1.lock"
    mkdir "$lock"
    printf '999999 dead\n' > "$lock/owner"

    run env FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" "$FLEET_ROOT/fleet.sh" replace ber1-tor-b --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"another change is in flight"* ]]
    [[ "$output" == *"999999"* ]]
    [[ "$output" == *"rm -rf"* ]]

    # untouched: nothing reclaimed it, so nothing could have raced a reclaimer
    [ -d "$lock" ]
    run cat "$lock/owner"
    [ "$output" = "999999 dead" ]
}

@test "two runs racing the same stale lock: neither takes it" {
    # The ordering that broke the previous fix: both read the dead owner, the
    # first clears and acquires, the second clears the first's lock and acquires
    # its own. With no clearing at all, the ordering cannot arise.
    lock="$BATS_TEST_TMPDIR/rack-fleet-race.lock"
    mkdir "$lock"
    printf '999999 dead\n' > "$lock/owner"
    claim() { if mkdir "$lock" 2>/dev/null; then echo acquired; else echo refused; fi; }
    a="$(claim)"; b="$(claim)"
    [ "$a" = "refused" ]
    [ "$b" = "refused" ]
    run cat "$lock/owner"
    [ "$output" = "999999 dead" ]
}

@test "the error names the pid and how to clear it by hand" {
    run grep -c 'rm -rf \$dir' "$FLEET_ROOT/fleet.sh"
    [ "$output" -ge 1 ]
    run grep -c 'races the first' "$FLEET_ROOT/fleet.sh"
    [ "$output" -ge 1 ]
}

@test "a live lock holder is never displaced" {
    lock="${FLEET_LOCK_DIR:-/tmp}/rack-fleet-livetest.lock"
    rm -rf "$lock"; mkdir "$lock"
    printf '%s a-real-run\n' "$$" > "$lock/owner"
    run env SITE=livetest bash -c '
        dir="${FLEET_LOCK_DIR:-/tmp}/rack-fleet-livetest.lock"
        if ! mkdir "$dir" 2>/dev/null; then
            owner="$(cat "$dir/owner" 2>/dev/null || echo unknown)"
            if [ "$owner" != unknown ] && ! kill -0 "${owner%% *}" 2>/dev/null; then
                echo "WRONGLY CLEARED"
            else
                echo "refused"
            fi
        fi'
    [ "$output" = "refused" ]
    rm -rf "$lock"
}

@test "the fake-switch tests need no route to the rack" {
    # route and ipconfig are stubbed, so these run on a laptop that has never
    # seen the rack's LAN. A test that only passes on one network is not a test.
    stub="$BATS_TEST_TMPDIR/routecheck"
    fake_switch_bin "$stub"
    [ -x "$stub/route" ]
    [ -x "$stub/ipconfig" ]
    run env PATH="$stub:$PATH" bash -c 'route -n get 203.0.113.99 | awk "/interface:/{print \$2}"'
    [ "$output" = "lo0" ]
    run env PATH="$stub:$PATH" bash -c 'ipconfig getifaddr lo0'
    [ "$output" = "127.0.0.1" ]
}

# --- finding and recovering a switch that moved ------------------------------

@test "the MAC normalises to the form macOS arp prints" {
    mac="d4:d6:df:03:d8:b2"
    short="${mac//:0/:}"; short="${short#0}"
    [ "$short" = "d4:d6:df:3:d8:b2" ]
}

@test "the ToRs carry a MAC, because the address is the thing that moves" {
    # Auto Install puts VLAN 1 on DHCP while it hunts for a provisioning server,
    # and a factory reset does the same. The MAC is then the only identifier
    # left, which is why it is recorded.
    for device in ber1-tor-a ber1-tor-b; do
        run jq -r --arg n "$device" '.devices[] | select(.name == $n) | .mac // "none"' "$SITE_FILE"
        [[ "$output" =~ ^[0-9a-f:]+$ ]]
    done
}

@test "locate refuses a device whose MAC is unknown rather than guessing" {
    site_without_mgmt_mac
    run "$FLEET_ROOT/fleet.sh" --site ber1-nomac locate ber1-mgmt
    [ "$status" -ne 0 ]
    [[ "$output" == *"no mac in the site definition"* ]]
}

@test "recover insists on being told where the switch currently is" {
    run "$FLEET_ROOT/fleet.sh" recover ber1-tor-b
    [ "$status" -eq 2 ]
    [[ "$output" == *"--from"* ]]
}



# --- recover must not save when recovery did not happen ----------------------

# A switch that answers, reports the name it is told to, and shows the running
# config it is given. Everything comes through the environment so the heredoc
# interpolates nothing.
recover_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/nc" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    cat > "$dir/ssh" <<'STUB'
#!/usr/bin/env bash
echo "SESSION $*" >> "$FAKE_LOG"
sleep 0.2
printf 'sw>'
while IFS= read -r line; do
    line="${line%$'\r'}"
    echo "CMD $line" >> "$FAKE_LOG"
    sleep 0.1
    printf '%s\r\n' "$line"
    if [ -n "$FAKE_REJECT" ] && [ "$line" = "$FAKE_REJECT" ]; then
        printf '\r\nError: Bad command\r\n\r\nsw#'
        continue
    fi
    case "$line" in
        logout) exit 0;;
        "show system-info") printf ' System Name          - %s\r\n' "$FAKE_NAME";;
        "show running-config") printf '%s\r\n' "$FAKE_RUNNING";;
        "show users") printf 'tid\tvty\tname\tsock\ttype\r\n4\t---\ttSsh00\t7\tSSH\r\n5\t---\ttSsh01\t9\tSSH\r\n';;
    esac
    printf '\r\nsw#'
done
STUB
    chmod +x "$dir/ssh" "$dir/nc"
    : > "$dir/log"
}

# run_recover <bindir> <name the switch reports> <its running config> [command to reject]
run_recover() {
    run env PATH="$1:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" \
        FAKE_LOG="$1/log" FAKE_NAME="$2" FAKE_RUNNING="$3" FAKE_REJECT="${4:-}" \
        "$FLEET_ROOT/fleet.sh" recover ber1-tor-b --from 192.0.2.50 --yes
}

@test "recover aborts when the switch refuses configure, and saves nothing" {
    # The failure that started this: the outer `|| true` swallowed a refused
    # `configure` as though it were the expected post-address disconnect, and
    # recovery went on to save whatever was already on the switch.
    bin="$BATS_TEST_TMPDIR/rc1"
    recover_stub "$bin"
    run_recover "$bin" ber1-tor-b "  ip address 192.168.0.12 255.255.255.0" "configure"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refused 'configure'"* ]]
    [[ "$output" == *"nothing was changed"* ]]
    run grep -c 'CMD ip address' "$bin/log"
    [ "$output" = "0" ]
    run grep -c 'CMD copy running-config startup-config' "$bin/log"
    [ "$output" = "0" ]
}

@test "recover aborts when the interface cannot be selected, and saves nothing" {
    bin="$BATS_TEST_TMPDIR/rc2"
    recover_stub "$bin"
    run_recover "$bin" ber1-tor-b "  ip address 192.168.0.12 255.255.255.0" "interface vlan 1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"interface vlan 1"* ]]
    run grep -c 'CMD copy running-config startup-config' "$bin/log"
    [ "$output" = "0" ]
}

@test "recover refuses to save when something else owns the target address" {
    # Something answering is not proof the right switch is there.
    bin="$BATS_TEST_TMPDIR/rc3"
    recover_stub "$bin"
    run_recover "$bin" some-other-switch "  ip address 192.168.0.12 255.255.255.0"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not ber1-tor-b"* ]]
    run grep -c 'CMD copy running-config startup-config' "$bin/log"
    [ "$output" = "0" ]
}

@test "recover refuses to save when the address did not actually take" {
    bin="$BATS_TEST_TMPDIR/rc4"
    recover_stub "$bin"
    run_recover "$bin" ber1-tor-b "  ip address 192.168.0.99 255.255.255.0"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not carry"* ]]
    run grep -c 'CMD copy running-config startup-config' "$bin/log"
    [ "$output" = "0" ]
}

@test "recover saves once the switch is the right one at the right address" {
    bin="$BATS_TEST_TMPDIR/rc5"
    recover_stub "$bin"
    run_recover "$bin" ber1-tor-b "  ip address 192.168.0.12 255.255.255.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"back at 192.168.0.12 and saved"* ]]
    run grep -c 'CMD ip address 192.168.0.12 255.255.255.0' "$bin/log"
    [ "$output" = "1" ]
    run grep -c 'CMD copy running-config startup-config' "$bin/log"
    [ "$output" = "1" ]
    # one session to move it, one to verify and save
    run grep -c '^SESSION' "$bin/log"
    [ "$output" = "2" ]
    # and the line session one could not log out of is cleared, after the save
    run grep -c 'CMD clear line 4' "$bin/log"
    [ "$output" = "1" ]
    run bash -c "grep -n 'CMD copy running-config\\|CMD clear line' '$bin/log' | cut -d: -f1 | paste -sd' ' -"
    set -- $output
    [ "$1" -lt "$2" ]
}

# --- apply is a confirmed commit ----------------------------------------------

# A switch that holds FAKE_BEFORE as its running configuration until it has been
# read once, then FAKE_AFTER, which is what the verification in the second
# session sees. The count lives in a file because each session is its own ssh.
apply_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/ssh" <<'STUB'
#!/usr/bin/env bash
echo "SESSION" >> "$FAKE_LOG"
sleep 0.2
printf 'sw>'
while IFS= read -r line; do
    line="${line%$'\r'}"
    echo "CMD $line" >> "$FAKE_LOG"
    sleep 0.1
    printf '%s\r\n' "$line"
    if [ -n "$FAKE_REJECT" ] && [ "$line" = "$FAKE_REJECT" ]; then
        printf '\r\nError: Bad command\r\n\r\nsw#'
        continue
    fi
    case "$line" in
        logout) exit 0;;
        "show running-config")
            reads=$(( $(cat "$FAKE_LOG.reads" 2>/dev/null || echo 0) + 1 ))
            echo "$reads" > "$FAKE_LOG.reads"
            if [ "$reads" -eq 1 ]; then cat "$FAKE_BEFORE"; else cat "$FAKE_AFTER"; fi | sed 's/$/\r/';;
        "show startup-config") sed 's/$/\r/' "$FAKE_STARTUP";;
        "reboot-schedule in "*) printf ' Reboot system in 5 minutes. Continue? (Y/N):'; continue;;
        Y) printf ' Reboot Schedule Settings\r\n Save before reboot: No\r\n';;
        "reboot-schedule cancel") printf ' Reboot schedule is cancelled.\r\n';;
    esac
    printf '\r\nsw#'
done
STUB
    chmod +x "$dir/ssh"
    : > "$dir/log"
}

# run_apply <bindir> <running before> <running after> <startup> [command to reject]
run_apply() {
    run env PATH="$1:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" FAKE_LOG="$1/log" \
        FAKE_BEFORE="$2" FAKE_AFTER="$3" FAKE_STARTUP="$4" FAKE_REJECT="${5:-}" \
        "$FLEET_ROOT/fleet.sh" apply ber1-tor-b --yes
}

# The render with lldp missing, which apply plans as a single command.
apply_fixtures() {
    rendered="$BATS_TEST_TMPDIR/rendered.cfg"
    drifted="$BATS_TEST_TMPDIR/drifted.cfg"
    fleet_render "$SITE_FILE" ber1-tor-b > "$rendered"
    grep -vx 'lldp' "$rendered" > "$drifted"
}

# Line number in the fake switch's log of the first command matching $2.
cmd_line() { grep -n -m1 -- "^CMD $2" "$1/log" | cut -d: -f1; }

@test "apply arms the rollback timer before changing anything, and cancels it only once verified" {
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/ap1"
    apply_stub "$bin"
    run_apply "$bin" "$drifted" "$rendered" "$drifted"
    [ "$status" -eq 0 ]
    [[ "$output" == *"applied, verified against the rendered configuration, and saved"* ]]
    arm="$(cmd_line "$bin" 'reboot-schedule in 5$')"
    change="$(cmd_line "$bin" 'lldp$')"
    cancel="$(cmd_line "$bin" 'reboot-schedule cancel$')"
    save="$(cmd_line "$bin" 'copy running-config startup-config$')"
    verify="$(grep -n '^CMD show running-config$' "$bin/log" | sed -n 2p | cut -d: -f1)"
    [ "$arm" -lt "$change" ]
    [ "$change" -lt "$verify" ]
    [ "$verify" -lt "$cancel" ]
    [ "$cancel" -lt "$save" ]
    # arming asks (Y/N) and was answered
    run grep -c '^CMD Y$' "$bin/log"
    [ "$output" = "1" ]
}

@test "apply saves nothing and leaves the timer armed when the switch does not verify" {
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/ap2"
    apply_stub "$bin"
    run_apply "$bin" "$drifted" "$drifted" "$drifted"
    [ "$status" -eq 13 ]
    [[ "$output" == *"reboots on its saved configuration"* ]]
    run grep -c '^CMD reboot-schedule cancel$' "$bin/log"
    [ "$output" = "0" ]
    run grep -c '^CMD copy running-config startup-config$' "$bin/log"
    [ "$output" = "0" ]
}

@test "apply leaves the timer armed when the switch rejects a command halfway" {
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/ap3"
    apply_stub "$bin"
    run_apply "$bin" "$drifted" "$rendered" "$drifted" "lldp"
    [ "$status" -eq 12 ]
    run grep -c '^CMD reboot-schedule cancel$' "$bin/log"
    [ "$output" = "0" ]
    run grep -c '^CMD copy running-config startup-config$' "$bin/log"
    [ "$output" = "0" ]
}

@test "apply changes nothing when the rollback timer cannot be armed" {
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/ap4"
    apply_stub "$bin"
    run_apply "$bin" "$drifted" "$rendered" "$drifted" "reboot-schedule in 5"
    [ "$status" -eq 16 ]
    [[ "$output" == *"nothing was changed"* ]]
    run grep -c '^CMD lldp$' "$bin/log"
    [ "$output" = "0" ]
    run grep -c '^CMD copy running-config startup-config$' "$bin/log"
    [ "$output" = "0" ]
}

@test "a global line apply will not remove is reported as global" {
    # Tab is whitespace to `read`, so an empty leading context used to vanish and
    # shift the command into its place: `[no lldp] ` instead of `[global] no lldp`.
    apply_fixtures
    printf 'no lldp\n' >> "$drifted"
    bin="$BATS_TEST_TMPDIR/ap6"
    apply_stub "$bin"
    run env PATH="$bin:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" FAKE_LOG="$bin/log" \
        FAKE_BEFORE="$drifted" FAKE_AFTER="$rendered" FAKE_STARTUP="$drifted" FAKE_REJECT="" \
        "$FLEET_ROOT/fleet.sh" apply ber1-tor-b --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[global] no lldp"* ]]
}

@test "apply refuses a switch with unsaved changes, which a rollback would discard" {
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/ap5"
    apply_stub "$bin"
    run_apply "$bin" "$drifted" "$rendered" "$rendered"
    [ "$status" -eq 11 ]
    [[ "$output" == *"unsaved changes"* ]]
    run grep -c '^CMD reboot-schedule' "$bin/log"
    [ "$output" = "0" ]
    run grep -c '^CMD lldp$' "$bin/log"
    [ "$output" = "0" ]
}

# --- zero touch: serving DHCP and TFTP on an isolated segment ----------------

ztp_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/op" <<'STUB'
#!/usr/bin/env bash
cat <<'JSON'
{"fields":[{"id":"username","value":"tuist"},{"id":"password","value":"ExampleNotReal24chars000"}]}
JSON
STUB
    cat > "$dir/ipconfig" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "getifaddr" ] && { echo "${FAKE_IFADDR:-192.168.50.1}"; exit 0; }
exit 1
STUB
    cat > "$dir/ifconfig" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$dir/op" "$dir/ipconfig" "$dir/ifconfig"
    # The fleet key is found through the site definition's `~/.ssh/...` path, so a
    # HOME of our own gives the served key without touching the real one.
    mkdir -p "$dir/home/.ssh"
    ssh-keygen -q -t rsa -b 2048 -N '' -f "$dir/home/.ssh/ber1-switch-rsa"
}

@test "ztp refuses without an interface, because it is a DHCP server" {
    run "$FLEET_ROOT/ztp.sh" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"isolated segment"* ]]
}

@test "ztp refuses the interface carrying the default route" {
    # The guard that matters: a second DHCP server on the network people are on
    # hands addresses to their laptops.
    local default
    default="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
    [ -n "$default" ] || skip "no default route on this machine to test against"
    run "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface "$default"
    [ "$status" -ne 0 ]
    [[ "$output" == *"default route"* ]]
}

@test "ztp refuses an interface with no address" {
    bin="$BATS_TEST_TMPDIR/ztp1"
    ztp_stub "$bin"
    cat > "$bin/ipconfig" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    chmod +x "$bin/ipconfig"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0
    [ "$status" -ne 0 ]
    [[ "$output" == *"no IPv4 address"* ]]
}

@test "ztp refuses when the 1Password item has no password" {
    # A switch provisioned from scratch has none of our credentials, so a config
    # without a login would leave it unreachable.
    bin="$BATS_TEST_TMPDIR/ztp2"
    ztp_stub "$bin"
    cat > "$bin/op" <<'STUB'
#!/usr/bin/env bash
echo '{"fields":[]}'
STUB
    chmod +x "$bin/op"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"no password"* ]]
}

@test "ztp serves a config that carries a login, keyed to the switch's MAC" {
    bin="$BATS_TEST_TMPDIR/ztp3"
    ztp_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -eq 0 ]
    # DHCP only, never DNS, and bound to the one interface
    [[ "$output" == *"port=0"* ]]
    [[ "$output" == *"interface=zzz0"* ]]
    [[ "$output" == *"bind-interfaces"* ]]
    # the boot file is offered to this switch by MAC, not to whoever asks
    [[ "$output" == *"dhcp-host=d4:d6:df:03:d8:b2,set:ber1-tor-b"* ]]
    # and nothing else on the segment is answered at all
    [[ "$output" == *"dhcp-ignore=tag:!known"* ]]
    [[ "$output" == *"67,\"ber1-tor-b.cfg\""* ]]
    # and the served file is the rendered config, with the login put back
    [[ "$output" == *'hostname "ber1-tor-b"'* ]]
    [[ "$output" == *"secret 0 <redacted>"* ]]
    # and the dry run writes nothing it should not: the password stays in 1Password
    root="$(sed -n 's/.*The files are in //p' <<<"$output")"
    run grep -rc ExampleNotReal24chars000 "$root"
    [[ "$output" != *":1"* ]]
}

# An op that knows no item until one is created, like a vault before a switch
# has ever been prepped.
ztp_empty_vault_stub() {
    local dir="$1"
    cat > "$dir/op" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
    "item get")
        [ -f "$FAKE_VAULT" ] || { echo "isn't an item" >&2; exit 1; }
        echo '{"fields":[{"id":"password","value":"GeneratedNotReal24chars0"}]}';;
    "item create") echo "CREATE $*" >> "$FAKE_VAULT.log"; touch "$FAKE_VAULT";;
esac
STUB
    chmod +x "$dir/op"
}

@test "ztp creates the 1Password item only when asked, and never in a dry run" {
    bin="$BATS_TEST_TMPDIR/ztp10"
    ztp_stub "$bin"
    ztp_empty_vault_stub "$bin"
    vault="$BATS_TEST_TMPDIR/vault"

    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_VAULT="$vault" \
        "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"--create-credentials"* ]]

    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_VAULT="$vault" \
        "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run --create-credentials
    [ "$status" -eq 0 ]
    [[ "$output" == *"a real run creates it"* ]]
    [ ! -e "$vault.log" ]

    cat > "$bin/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
    cat > "$bin/dnsmasq" <<'STUB'
#!/usr/bin/env bash
root="$(sed -n 's/^tftp-root=//p' "${1#--conf-file=}")"
cp "$root/ber1-tor-b.cfg" "$FAKE_COPY"
STUB
    chmod +x "$bin/sudo" "$bin/dnsmasq"
    copy="$BATS_TEST_TMPDIR/created.cfg"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_VAULT="$vault" FAKE_COPY="$copy" \
        "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --create-credentials < /dev/null
    [ "$status" -eq 0 ]
    run grep -c -- '--generate-password=letters,digits,24' "$vault.log"
    [ "$output" = "1" ]
    run bash -c "tr -d '\r\000' < '$copy' | grep -c 'secret 0 GeneratedNotReal24chars0$'"
    [ "$output" = "1" ]
}

@test "ztp refuses a password the switch would not accept" {
    bin="$BATS_TEST_TMPDIR/ztp8"
    ztp_stub "$bin"
    cat > "$bin/op" <<'STUB'
#!/usr/bin/env bash
echo '{"fields":[{"id":"password","value":"has a space"}]}'
STUB
    chmod +x "$bin/op"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"not one the switch accepts"* ]]
}

@test "a real run serves the password as secret 0 and deletes it once serving stops" {
    bin="$BATS_TEST_TMPDIR/ztp9"
    ztp_stub "$bin"
    cat > "$bin/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
    # dnsmasq keeps a copy of what it would have served, then stops as though
    # the operator pressed Ctrl-C.
    cat > "$bin/dnsmasq" <<'STUB'
#!/usr/bin/env bash
conf="${1#--conf-file=}"
root="$(sed -n 's/^tftp-root=//p' "$conf")"
cp "$root/ber1-tor-b.cfg" "$FAKE_COPY"
echo "$root" > "$FAKE_COPY.root"
STUB
    chmod +x "$bin/sudo" "$bin/dnsmasq"
    copy="$BATS_TEST_TMPDIR/served.cfg"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_COPY="$copy" \
        "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 < /dev/null
    [ "$status" -eq 0 ]
    run bash -c "tr -d '\r\000' < '$copy' | grep -c '^user name tuist privilege admin secret 0 ExampleNotReal24chars000$'"
    [ "$output" = "1" ]
    [ ! -e "$(cat "$copy.root")" ]
}

@test "ztp has the switch fetch the fleet key before the file moves it off this segment" {
    # Auto Install fetches only the configuration, and the key is not a
    # configuration line, so the served file has to download it. Once the file
    # reaches `interface vlan` the switch is on its site address and can no
    # longer reach this TFTP server.
    bin="$BATS_TEST_TMPDIR/ztp6"
    ztp_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -eq 0 ]
    root="$(sed -n 's/.*The files are in //p' <<<"$output")"
    served="$root/ber1-tor-b.cfg"
    download="$(tr -d '\r\000' < "$served" | grep -nx 'ip ssh download v2 fleet.pub ip-address 192.168.50.1' | cut -d: -f1)"
    address="$(tr -d '\r\000' < "$served" | grep -n '^interface vlan ' | head -1 | cut -d: -f1)"
    [ -n "$download" ]
    [ "$download" -lt "$address" ]
    run head -1 "$root/fleet.pub"
    [ "$output" = "---- BEGIN SSH2 PUBLIC KEY ----" ]
}

@test "ztp refuses an ed25519 fleet key, which the firmware rejects" {
    bin="$BATS_TEST_TMPDIR/ztp7"
    ztp_stub "$bin"
    rm -f "$bin/home/.ssh/ber1-switch-rsa" "$bin/home/.ssh/ber1-switch-rsa.pub"
    ssh-keygen -q -t ed25519 -N '' -f "$bin/home/.ssh/ber1-switch-rsa"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"ed25519"* ]]
}

# --via: serving from a Linux machine over SSH. The ssh stub runs the remote
# command here, against an `ip` shaped like ber1-edge: two default routes on its
# SFP+ ports, and enp89s0 addressed on the isolated segment.
ztp_via_stub() {
    local dir="$1"
    ztp_stub "$dir"
    cat > "$dir/ssh" <<'STUB'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
    case "$1" in -o) shift 2;; -*) shift;; *) break;; esac
done
echo "SSH $1" >> "$FAKE_LOG"; shift
exec bash -c "$*"
STUB
    cat > "$dir/ip" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    "route show default")
        echo "default via 192.168.0.1 dev enp2s0f0np0 proto dhcp src 192.168.0.157 metric 100"
        echo "default via 192.168.0.1 dev enp2s0f1np1 proto dhcp src 192.168.0.158 metric 100";;
    "link show dev enp89s0"|"link show dev enp2s0f1np1") echo "5: $4: <BROADCAST,UP>";;
    "link show dev "*) exit 1;;
    "-4 -o addr show dev enp89s0") echo "5: enp89s0    inet 192.168.50.1/24 brd 192.168.50.255 scope global enp89s0";;
esac
STUB
    chmod +x "$dir/ssh" "$dir/ip"
    : > "$dir/log"
}

@test "--via refuses the server's default route, on any of its uplinks" {
    bin="$BATS_TEST_TMPDIR/via1"
    ztp_via_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface enp2s0f1np1 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"carries tuist@edge's default route"* ]]
    run grep -c '^SSH tuist@edge' "$bin/log"
    [ "$output" -ge 1 ]
}

@test "--via refuses an interface name that could smuggle a command" {
    bin="$BATS_TEST_TMPDIR/via2"
    ztp_via_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface 'enp89s0;true' --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"not an interface name"* ]]
    run cat "$bin/log"
    [ -z "$output" ]
}

@test "--via serves from the server, and removes what it copied there when it stops" {
    bin="$BATS_TEST_TMPDIR/via3"
    ztp_via_stub "$bin"
    cat > "$bin/sudo" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "-n" ] && shift
exec "$@"
STUB
    cat > "$bin/dnsmasq" <<'STUB'
#!/usr/bin/env bash
conf="${1#--conf-file=}"
root="$(sed -n 's/^tftp-root=//p' "$conf")"
cp "$root/ber1-mgmt.cfg" "$FAKE_COPY"
cp "$conf" "$FAKE_COPY.conf"
echo "$root" > "$FAKE_COPY.root"
STUB
    chmod +x "$bin/sudo" "$bin/dnsmasq"
    copy="$BATS_TEST_TMPDIR/via-served.cfg"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" FAKE_COPY="$copy" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface enp89s0 < /dev/null
    [ "$status" -eq 0 ]
    # the key comes from the server's own address on the segment
    run bash -c "tr -d '\r\000' < '$copy' | grep -c '^ip ssh download v2 fleet.pub ip-address 192.168.50.1$'"
    [ "$output" = "1" ]
    run bash -c "tr -d '\r\000' < '$copy' | grep -c '^user name tuist privilege admin secret 0 ExampleNotReal24chars000$'"
    [ "$output" = "1" ]
    # dnsmasq drops to the owner of the directory, which is the only one who can read it
    run grep -c "^user=$(id -un)$" "$copy.conf"
    [ "$output" = "1" ]
    [ ! -e "$(cat "$copy.root")" ]
}

@test "--via stops dnsmasq and removes the files on the server when this end is killed outright" {
    # What happened on ber1-edge: this end was killed, no trap ran, and dnsmasq
    # kept serving with the password still on disk.
    bin="$BATS_TEST_TMPDIR/via4"
    ztp_via_stub "$bin"
    cat > "$bin/sudo" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "-n" ] && shift
exec "$@"
STUB
    cat > "$bin/dnsmasq" <<'STUB'
#!/usr/bin/env bash
sed -n 's/^tftp-root=//p' "${1#--conf-file=}" > "$FAKE_STATE.root"
echo $$ > "$FAKE_STATE.pid"
exec sleep 300
STUB
    chmod +x "$bin/sudo" "$bin/dnsmasq"
    state="$BATS_TEST_TMPDIR/via4-state"
    env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" FAKE_STATE="$state" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface enp89s0 < /dev/null > /dev/null 2>&1 3>&- &
    ztp=$!
    for _ in $(seq 1 50); do [ -s "$state.pid" ] && break; sleep 0.2; done
    [ -s "$state.pid" ]
    served="$(cat "$state.pid")"
    kill -9 "$ztp"
    for _ in $(seq 1 50); do ps -p "$served" >/dev/null 2>&1 || break; sleep 0.2; done
    kill "$served" 2>/dev/null || true
    run ps -p "$served"
    [ "$status" -ne 0 ]
    [ ! -e "$(cat "$state.root")" ]
}

@test "ztp offers no boot file by MAC when the site definition has none" {
    bin="$BATS_TEST_TMPDIR/ztp4"
    ztp_stub "$bin"
    site_without_mgmt_mac
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" --site ber1-nomac ber1-mgmt --interface zzz0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"dhcp-boot=ber1-mgmt.cfg"* ]]
    [[ "$output" == *"no mac in the site definition"* ]]
}

@test "ztp reports a missing dnsmasq during the dry run, not after you confirm" {
    bin="$BATS_TEST_TMPDIR/ztp5"
    ztp_stub "$bin"
    # a PATH with the stubs and the basics, but deliberately no dnsmasq
    run env PATH="$bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" \
        ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"dnsmasq"* ]]
}

# --- reading show users, from real output on 2026-09-22 ----------------------

@test "the current connection is the newest task, not the first one listed" {
    # Preflight on ber1-tor-b listed tSsh00 (a line recover leaked) and tSsh02
    # (itself), and reported "connection 1" because it read the first match.
    users="$(printf 'tid\tvty\tname\tsock\ttype\n4\t---\ttSsh00\t7\tSSH\n5\t---\ttSsh02\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_current_connection"
    [ "$output" = "02" ]
}

@test "recover's leaked line is the task directly below the session that follows it" {
    users="$(printf 'tid\tvty\tname\tsock\ttype\n4\t---\ttSsh05\t7\tSSH\n6\t---\ttSsh06\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_predecessor_line"
    [ "$output" = "4" ]
}

@test "a line that is not the direct predecessor is left alone" {
    # It could be an operator's own SSH or web session. Clearing whatever else is
    # listed would reach it; matching the one task number session one had does not.
    users="$(printf 'tid\tvty\tname\tsock\ttype\n4\t---\ttSsh00\t7\tSSH\n5\t---\ttSsh02\t9\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_predecessor_line"
    [ -z "$output" ]
}

@test "with only its own line listed, there is nothing to clear" {
    users="$(printf 'tid\tvty\tname\tsock\ttype\n5\t---\ttSsh03\t8\tSSH\n')"
    run fleet_sh "printf '%s' '$users' | fleet_predecessor_line"
    [ -z "$output" ]
}
