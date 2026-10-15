#!/usr/bin/env bats
# The file replace pushes, and replacing a switch's whole configuration over
# TFTP.

load helpers

# --- the file that would be pushed -------------------------------------------
#
# The TFTP export turned out to be text, so a whole-config replace is possible.
# The fixture is a real export off ber1-tor-b with the hash replaced.

export_fixture() { echo "$FLEET_ROOT/tests/fixtures/ber1-tor-b-tftp-export.cfg"; }

@test "the exported file and the render describe the same configuration" {
    desired="$BATS_TEST_TMPDIR/desired.cfg"
    render_as_captured ber1-tor-b > "$desired"
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
    render_as_captured ber1-tor-b > "$desired"
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
    jq '.services.lldp = false' "$FLEET_ROOT/sites/ber1-standalone.json" > "$site"

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
    render_as_captured ber1-tor-b > "$desired"
    fleet_merge_unmanaged "$current" "$desired" > "$merged"

    run fleet_removed_lines "$current" "$merged"
    [[ "$output" == *"radius-server host 10.0.0.5"* ]]
}

@test "nothing is reported as lost when the switch already matches" {
    current="$BATS_TEST_TMPDIR/same.cfg"
    grep -v '^!' "$(export_fixture)" > "$current"
    desired="$BATS_TEST_TMPDIR/desired3.cfg"
    merged="$BATS_TEST_TMPDIR/merged3.cfg"
    render_as_captured ber1-tor-b > "$desired"
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
    render_as_captured ber1-tor-b | sed 's/^lldp$/no lldp/' > "$desired"
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
    render_as_captured ber1-tor-b > "$desired"
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

