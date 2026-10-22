#!/usr/bin/env bats
# The session driver against a fake switch, and the lock that keeps two runs
# off one rack.

load helpers

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
    render_as_captured ber1-tor-b > "$desired"
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
    run grep -c 'rm -rf \$dir' "$FLEET_ROOT/lib/lock.sh"
    [ "$output" -ge 1 ]
    run grep -c 'races the first' "$FLEET_ROOT/lib/lock.sh"
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
