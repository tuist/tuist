#!/usr/bin/env bats
# apply as a confirmed commit: the rollback timer is armed before a change and
# cancelled only once the switch verifies.

load helpers

# --- apply is a confirmed commit ----------------------------------------------

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
    verify="$(grep -n '^CMD show running-config$' "$bin/log" | tail -1 | cut -d: -f1)"
    [ "$arm" -lt "$change" ]
    [ "$change" -lt "$verify" ]
    [ "$verify" -lt "$cancel" ]
    [ "$cancel" -lt "$save" ]
    # arming asks (Y/N) and was answered
    run grep -c '^CMD Y$' "$bin/log"
    [ "$output" = "1" ]
    # cancelled, so nothing is left holding the rack
    [ ! -e "$BATS_TEST_TMPDIR/rack-fleet-ber1.rollback" ]
}

@test "apply saves nothing and leaves the timer armed when the switch does not verify" {
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/ap2"
    apply_stub "$bin"
    run_apply "$bin" "$drifted" "$drifted" "$drifted"
    [ "$status" -eq 13 ]
    [[ "$output" == *"reboots on its saved configuration"* ]]
    [ -f "$BATS_TEST_TMPDIR/rack-fleet-ber1.rollback" ]
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
    [ -f "$BATS_TEST_TMPDIR/rack-fleet-ber1.rollback" ]
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
    # the switch is unchanged, so the apply ordering still stops the next one
    [ ! -e "$BATS_TEST_TMPDIR/rack-fleet-ber1.rollback" ]
    run grep -c '^CMD lldp$' "$bin/log"
    [ "$output" = "0" ]
    run grep -c '^CMD copy running-config startup-config$' "$bin/log"
    [ "$output" = "0" ]
}

