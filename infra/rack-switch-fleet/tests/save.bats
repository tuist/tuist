#!/usr/bin/env bats
# Sealing a switch that rack:ztp provisioned: save, preflight and publish.

load helpers

# --- sealing a switch that rack:ztp provisioned ------------------------------

@test "preflight flags a startup configuration that is still the provisioning file" {
    # Auto Install saves what it fetched verbatim: the login in plaintext and a
    # key download that runs at every boot.
    apply_fixtures
    unsealed="$BATS_TEST_TMPDIR/unsealed.cfg"
    { cat "$rendered"; echo "user name tuist privilege admin secret 0 NotARealPassword1"; \
      echo "ip ssh download v2 fleet.pub ip-address 192.168.50.1"; } > "$unsealed"
    bin="$BATS_TEST_TMPDIR/seal1"
    apply_stub "$bin"
    # preflight writes a backup, so it runs from a copy rather than over the
    # committed one
    copy="$BATS_TEST_TMPDIR/fleet-copy"
    cp -R "$FLEET_ROOT" "$copy"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_BEFORE="$rendered" FAKE_AFTER="$rendered" \
        FAKE_STARTUP="$unsealed" FAKE_REJECT="" "$copy/fleet.sh" preflight ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"mise run rack:fleet save ber1-tor-b"* ]]
    # and the backup it writes does not carry the password
    run grep -c NotARealPassword1 "$copy/backups/ber1/ber1-tor-b.cfg"
    [ "$output" = "0" ]
}

@test "save writes the running configuration only once it matches the render" {
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/seal2"
    apply_stub "$bin"
    run env PATH="$bin:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" FAKE_LOG="$bin/log" \
        FAKE_BEFORE="$drifted" FAKE_AFTER="$drifted" FAKE_STARTUP="$drifted" FAKE_REJECT="" \
        "$FLEET_ROOT/fleet.sh" save ber1-tor-b
    [ "$status" -eq 11 ]
    run grep -c '^CMD copy running-config startup-config$' "$bin/log"
    [ "$output" = "0" ]

    bin="$BATS_TEST_TMPDIR/seal3"
    apply_stub "$bin"
    run env PATH="$bin:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" FAKE_LOG="$bin/log" \
        FAKE_BEFORE="$rendered" FAKE_AFTER="$rendered" FAKE_STARTUP="$rendered" FAKE_REJECT="" \
        "$FLEET_ROOT/fleet.sh" save ber1-tor-b
    [ "$status" -eq 0 ]
    run grep -c '^CMD copy running-config startup-config$' "$bin/log"
    [ "$output" = "1" ]
    run grep -c '^SESSION' "$bin/log"
    [ "$output" = "1" ]
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

@test "an unsaved change to a line the render does not own still blocks apply" {
    # The login is not the render's, so it is not drift, but a rollback returns
    # it to the saved one all the same.
    apply_fixtures
    running="$BATS_TEST_TMPDIR/running.cfg"
    saved="$BATS_TEST_TMPDIR/saved.cfg"
    { cat "$drifted"; echo "user name admin privilege admin secret 5 EXAMPLEHASHNOTREAL-new"; } > "$running"
    { cat "$drifted"; echo "user name admin privilege admin secret 5 EXAMPLEHASHNOTREAL-old"; } > "$saved"
    bin="$BATS_TEST_TMPDIR/ap7"
    apply_stub "$bin"
    run_apply "$bin" "$running" "$rendered" "$saved"
    [ "$status" -eq 11 ]
    [[ "$output" == *"unsaved changes"* ]]
    run grep -c '^CMD reboot-schedule' "$bin/log"
    [ "$output" = "0" ]
    run grep -c '^CMD lldp$' "$bin/log"
    [ "$output" = "0" ]
}

@test "pager noise and padding are not an unsaved change" {
    # The two reads come off the same switch, so only terminal noise can tell
    # them apart when nothing is unsaved.
    apply_fixtures
    padded="$BATS_TEST_TMPDIR/padded.cfg"
    { printf '!ignored banner\n#\n'; sed 's/^\(hostname .*\)$/\1   /' "$drifted"; printf '#\n#\n'; } > "$padded"
    bin="$BATS_TEST_TMPDIR/ap8"
    apply_stub "$bin"
    run_apply "$bin" "$drifted" "$rendered" "$padded"
    [ "$status" -eq 0 ]
    [[ "$output" == *"applied, verified against the rendered configuration, and saved"* ]]
}

@test "an unsaved change made while apply waited for its confirmation still blocks it" {
    # The plan is read before the prompt, and a change made during the prompt
    # is not in that read.
    apply_fixtures
    changed="$BATS_TEST_TMPDIR/changed.cfg"
    { cat "$drifted"; echo "user name admin privilege admin secret 5 EXAMPLEHASHNOTREAL-new"; } > "$changed"
    bin="$BATS_TEST_TMPDIR/ap9"
    apply_stub "$bin"
    run env PATH="$bin:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" FAKE_LOG="$bin/log" \
        FAKE_BEFORE="$drifted" FAKE_MEANWHILE="$changed" FAKE_AFTER="$rendered" FAKE_STARTUP="$drifted" FAKE_REJECT="" \
        "$FLEET_ROOT/fleet.sh" apply ber1-tor-b --yes
    [ "$status" -eq 11 ]
    [[ "$output" == *"unsaved changes"* ]]
    run grep -c '^CMD reboot-schedule in' "$bin/log"
    [ "$output" = "0" ]
}

@test "apply changes nothing on a switch that was changed after its plan was read" {
    # Somebody applied and saved in between: nothing is unsaved, but the plan is
    # stale.
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/ap10"
    apply_stub "$bin"
    run env PATH="$bin:$PATH" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" FAKE_LOG="$bin/log" \
        FAKE_BEFORE="$drifted" FAKE_MEANWHILE="$rendered" FAKE_AFTER="$rendered" FAKE_STARTUP="$rendered" FAKE_REJECT="" \
        "$FLEET_ROOT/fleet.sh" apply ber1-tor-b --yes
    [ "$status" -eq 17 ]
    [[ "$output" == *"ber1-tor-b changed after its plan was read"* ]]
    run grep -c '^CMD reboot-schedule in' "$bin/log"
    [ "$output" = "0" ]
    [ ! -e "$BATS_TEST_TMPDIR/rack-fleet-ber1.rollback" ]
}

@test "publish writes to the namespace the site belongs to, not whatever is current" {
    apply_fixtures
    bin="$BATS_TEST_TMPDIR/publish1"
    apply_stub "$bin"
    copy="$BATS_TEST_TMPDIR/fleet-copy"
    cp -R "$FLEET_ROOT" "$copy"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_BEFORE="$rendered" FAKE_AFTER="$rendered" \
        FAKE_STARTUP="$rendered" FAKE_REJECT="" "$copy/fleet.sh" publish ber1-tor-b --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"status in namespace tuist:"* ]]
}
