#!/usr/bin/env bats
# Finding a switch that moved and putting it back, and why recover refuses to
# save.

load helpers

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
#
# `show users` lists "tid name" pairs, comma separated: FAKE_USERS_1 in the
# first session and FAKE_USERS_2 in the second. By default session one is the
# only line, and in session two it is still there, leaked, below session two.
recover_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/nc" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    cat > "$dir/ssh" <<'STUB'
#!/usr/bin/env bash
session=$(( $(cat "$FAKE_LOG.sessions" 2>/dev/null || echo 0) + 1 ))
echo "$session" > "$FAKE_LOG.sessions"
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
        "show users")
            if [ "$session" -eq 1 ]; then rows="${FAKE_USERS_1-4 tSsh00}"; else rows="${FAKE_USERS_2-4 tSsh00,5 tSsh01}"; fi
            printf 'tid\tvty\tname\tsock\ttype\r\n'
            IFS=, read -ra listed <<<"$rows"
            for row in "${listed[@]}"; do
                printf '%s\t---\t%s\t7\tSSH\r\n' "${row% *}" "${row#* }"
            done;;
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

@test "recover leaves alone an operator who connected between its two sessions" {
    # Session one is tSsh00 on line 4. Someone else's tSsh01 on line 5 now sits
    # directly below session two, where the leaked line used to be looked for.
    bin="$BATS_TEST_TMPDIR/rc6"
    recover_stub "$bin"
    export FAKE_USERS_2="4 tSsh00,5 tSsh01,6 tSsh02"
    run_recover "$bin" ber1-tor-b "  ip address 192.168.0.12 255.255.255.0"
    [ "$status" -eq 0 ]
    run grep -c 'CMD clear line 5' "$bin/log"
    [ "$output" = "0" ]
    run grep -c 'CMD clear line 4' "$bin/log"
    [ "$output" = "1" ]
}

@test "recover clears nothing when session one's line has gone and its tid was reused" {
    # Line 4 is somebody else's tSsh01 now, not session one's tSsh00.
    bin="$BATS_TEST_TMPDIR/rc7"
    recover_stub "$bin"
    export FAKE_USERS_2="4 tSsh01,6 tSsh02"
    run_recover "$bin" ber1-tor-b "  ip address 192.168.0.12 255.255.255.0"
    [ "$status" -eq 0 ]
    recovered="$output"
    run grep -c 'CMD clear line' "$bin/log"
    [ "$output" = "0" ]
    [[ "$recovered" == *"mise run rack:fleet sessions ber1-tor-b <tid>"* ]]
}

@test "recover clears nothing when it could not tell which line session one held" {
    bin="$BATS_TEST_TMPDIR/rc8"
    recover_stub "$bin"
    export FAKE_USERS_1=""
    run_recover "$bin" ber1-tor-b "  ip address 192.168.0.12 255.255.255.0"
    [ "$status" -eq 0 ]
    recovered="$output"
    run grep -c 'CMD clear line' "$bin/log"
    [ "$output" = "0" ]
    [[ "$recovered" == *"mise run rack:fleet sessions ber1-tor-b <tid>"* ]]
}
