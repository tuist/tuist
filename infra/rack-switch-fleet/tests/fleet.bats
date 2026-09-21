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
    [[ "$output" == *"closed the session"* ]]
}

# --- the port map, the join between machines and switch ports ----------------

@test "the port map merges node links with the switch's own ports" {
    run fleet_port_map "$SITE_FILE" ber1-tor-b
    [[ "$output" == *"25"*"node"*"ber1-edge"*"edge"* ]]
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
    # ber1-edge reaches both ToRs; ber1-svc reaches only ToR B, which is the
    # rack risk the note on it records. Adding its second link is a data edit.
    run jq -r '[.nodes[] | select(.name == "ber1-edge") | .links[].switch] | sort | join(",")' "$SITE_FILE"
    [ "$output" = "ber1-tor-a,ber1-tor-b" ]
    run jq -r '[.nodes[] | select(.name == "ber1-svc") | .links[].switch] | join(",")' "$SITE_FILE"
    [ "$output" = "ber1-tor-b" ]
}

@test "the storage pair is split one node per ToR" {
    # Deliberate, and the same split as the ATS chains: losing a ToR must cost
    # one storage node and never both. Tidying them onto one switch would remove
    # the redundancy without looking like it removed anything, so it fails here.
    run jq -r '[.nodes[] | select(.role == "storage") | .links[].switch] | sort | unique | length' "$SITE_FILE"
    [ "$output" = "2" ]
    run jq -r '[.nodes[] | select(.role == "storage")] | length' "$SITE_FILE"
    [ "$output" = "2" ]
    run jq -r '[.nodes[] | select(.role == "storage") | select((.links | length) != 1)] | length' "$SITE_FILE"
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

@test "a node with no management link at all is rejected" {
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
