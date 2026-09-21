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
# A switch that echoes like the real one: prompt, echoed command, output.
printf 'ber1-tor-b>'
while IFS= read -r line; do
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
