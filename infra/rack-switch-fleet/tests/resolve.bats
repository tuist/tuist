#!/usr/bin/env bats
# A rollback that may still be pending holds the rack until resolve lifts it.

load helpers

# --- a rollback that may still be pending holds the rack ---------------------

HOLD_RECORD_NAME="rack-fleet-ber1.rollback"

# A hold on ber1-tor-b whose timer was armed $1 seconds ago, as apply writes it.
hold_rollback() {
    local armed
    armed=$(( $(date +%s) - $1 ))
    printf 'device ber1-tor-b\naddress 192.168.0.12\narmed %s\nfires %s\n' "$armed" "$(( armed + 300 ))" \
        > "$BATS_TEST_TMPDIR/$HOLD_RECORD_NAME"
}

# run_resolve <bindir> <running> <startup> [device]
run_resolve() {
    run env PATH="$1:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" FAKE_LOG="$1/log" \
        FAKE_BEFORE="$2" FAKE_AFTER="$2" FAKE_STARTUP="$3" FAKE_REJECT="" \
        "$FLEET_ROOT/fleet.sh" resolve "${4:-ber1-tor-b}"
}

@test "a rollback left pending holds the rack, so the other ToR is not changed during it" {
    # ber1-tor-b already matched the render when its timer could not be
    # cancelled, so it passes the apply ordering while minutes from rebooting.
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/hold1"
    apply_stub "$bin"
    run_apply "$bin" "$drifted" "$rendered" "$drifted" "reboot-schedule cancel"
    [ "$status" -eq 14 ]
    failed="$output"
    : > "$bin/log"
    run env PATH="$bin:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" FAKE_LOG="$bin/log" \
        FAKE_BEFORE="$rendered" FAKE_AFTER="$rendered" FAKE_STARTUP="$rendered" FAKE_REJECT="" \
        "$FLEET_ROOT/fleet.sh" apply ber1-tor-a --yes
    [ "$status" -ne 0 ]
    refused="$output"
    # refused before any switch was touched
    run grep -c '^SESSION' "$bin/log"
    [ "$output" = "0" ]
    [[ "$refused" == *"ber1-tor-b may still be rolling back"* ]]
    [[ "$refused" == *"mise run rack:fleet resolve ber1-tor-b"* ]]
    [[ "$failed" == *"mise run rack:fleet resolve ber1-tor-b"* ]]
    # and a later run never lifts it on its own
    [ -f "$BATS_TEST_TMPDIR/$HOLD_RECORD_NAME" ]
    [ ! -e "$BATS_TEST_TMPDIR/rack-fleet-ber1.lock" ]
}

@test "resolve lifts the hold once the switch is back on its saved configuration" {
    apply_fixtures
    hold_rollback 1200
    bin="$BATS_TEST_TMPDIR/resolve1"
    apply_stub "$bin"
    run_resolve "$bin" "$drifted" "$drifted"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ber1 is no longer held"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/$HOLD_RECORD_NAME" ]
    # one connection, and nothing sent that changes the switch
    run grep -c '^SESSION' "$bin/log"
    [ "$output" = "1" ]
    run grep -cE '^CMD (configure|copy|reboot|clear)' "$bin/log"
    [ "$output" = "0" ]
}

@test "resolve keeps the hold while the switch still differs from its saved configuration" {
    apply_fixtures
    hold_rollback 1200
    bin="$BATS_TEST_TMPDIR/resolve2"
    apply_stub "$bin"
    run_resolve "$bin" "$rendered" "$drifted"
    [ "$status" -ne 0 ]
    [[ "$output" == *"still differs from its saved one"* ]]
    [ -f "$BATS_TEST_TMPDIR/$HOLD_RECORD_NAME" ]

    # every line counts, the login included, as it does before apply arms a timer
    running="$BATS_TEST_TMPDIR/running.cfg"
    saved="$BATS_TEST_TMPDIR/saved.cfg"
    { cat "$drifted"; echo "user name admin privilege admin secret 5 EXAMPLEHASHNOTREAL-new"; } > "$running"
    { cat "$drifted"; echo "user name admin privilege admin secret 5 EXAMPLEHASHNOTREAL-old"; } > "$saved"
    run_resolve "$bin" "$running" "$saved"
    [ "$status" -ne 0 ]
    [[ "$output" == *"still differs from its saved one"* ]]
    [ -f "$BATS_TEST_TMPDIR/$HOLD_RECORD_NAME" ]
}

@test "resolve will not lift the hold before the timer and a reboot can have finished" {
    # Until then running matching startup does not prove the reboot happened:
    # the change saved by hand reads the same, with the reboot still to come.
    apply_fixtures
    hold_rollback 60
    bin="$BATS_TEST_TMPDIR/resolve3"
    apply_stub "$bin"
    run_resolve "$bin" "$drifted" "$drifted"
    [ "$status" -ne 0 ]
    [[ "$output" == *"resolve it after"* ]]
    [ -f "$BATS_TEST_TMPDIR/$HOLD_RECORD_NAME" ]
    # and it did not spend a connection finding that out
    run grep -c '^SESSION' "$bin/log"
    [ "$output" = "0" ]
}

@test "resolve only lifts a hold for the switch it is on" {
    hold_rollback 1200
    run env FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" "$FLEET_ROOT/fleet.sh" resolve ber1-tor-a
    [ "$status" -ne 0 ]
    [[ "$output" == *"held for ber1-tor-b, not ber1-tor-a"* ]]
    [ -f "$BATS_TEST_TMPDIR/$HOLD_RECORD_NAME" ]
}
