# shellcheck shell=bash
# What every file of the rack switch fleet suite shares: the copy of the fleet
# it runs against, the fixtures, the network guard, and the fake switches more
# than one file drives. Loaded by each file with `load helpers`.
#
# The interesting fixture is a real `show running-config` transcript taken off
# ber1-tor-b, pager artefacts and all. Its NUL bytes are written as the two
# characters \0 so the fixture stays reviewable in a diff, and are decoded here.

setup_file() {
    # Each file runs against its own copy of this directory and of the charts
    # it renders into, so files run side by side and a test that renders into,
    # edits or adds to the committed files never touches the checkout.
    local checkout="$BATS_FILE_TMPDIR/checkout"
    mkdir -p "$checkout/infra"
    cp -R "$BATS_TEST_DIRNAME/../../helm" "$checkout/infra/helm"
    cp -R "$BATS_TEST_DIRNAME/.." "$checkout/infra/rack-switch-fleet"
    FLEET_ROOT="$checkout/infra/rack-switch-fleet"
    export FLEET_ROOT
    # The site's machines reference their RackHosts in the tuist chart's values,
    # which a test that runs the tools from a copy of this directory would
    # otherwise look for beside the copy. Those of the env the rack is in.
    source "$FLEET_ROOT/lib/config.sh"
    FLEET_RACK_VALUES="$(cd "$FLEET_ROOT/../helm/tuist" && pwd)/values-managed-$(fleet_site_env "$FLEET_ROOT/sites/ber1.json").yaml"
    export FLEET_RACK_VALUES
    export FIXTURE="$BATS_TEST_DIRNAME/fixtures/ber1-tor-b-running-config.txt"

    export TRANSCRIPT="$BATS_FILE_TMPDIR/transcript.txt"
    perl -pe 's/\\0/\x00/g' "$FIXTURE" > "$TRANSCRIPT"

    # The config body alone, cut with sed so the extractor under test is not
    # used to build its own input.
    export BODY="$BATS_FILE_TMPDIR/body.txt"
    sed -n '/#show running-config$/,$p' "$TRANSCRIPT" | sed '1d;$d' > "$BODY"

    # The site definition is the real rack's, so a test that gets past a guard
    # it meant to trip talks to a real switch, and a switch allows only a few
    # connections per boot. Every command that leaves this machine fails here
    # unless the test puts its own stub ahead of these on PATH.
    local guard="$BATS_FILE_TMPDIR/no-network"
    mkdir -p "$guard"
    for tool in ssh scp curl kubectl op nc telnet tftp; do
        printf '#!/bin/sh\necho "test reached the real %s: $*" >&2\nexit 97\n' "$tool" > "$guard/$tool"
        chmod +x "$guard/$tool"
    done
    export PATH="$guard:$PATH"
}

setup() {
    source "$FLEET_ROOT/lib/config.sh"
    SITE_FILE="$(fleet_site_file ber1)"
    # Each test takes the rack's lock in a directory of its own, not the
    # operator's, so tests running side by side never hold it for each other.
    export FLEET_LOCK_DIR="$BATS_TEST_TMPDIR"
    # The SSH write paths are for switches the controller has not adopted, and the
    # rack's ToRs now are. The tools under test run against the site with its ToRs
    # standalone, as before they were adopted, unless a test names another site.
    jq '(.devices[] | select(.role == "tor")) |= del(.adopted)' "$SITE_FILE" \
        > "$FLEET_ROOT/sites/ber1-standalone.json"
    export RACK_SITE=ber1-standalone
}

# The site as it was before it had a WAN of its own, for the tests of what an
# edge does on a management VLAN that reaches the internet by itself.
site_without_wan() {
    jq '.management.edge.wan = {vlan: null, address: null} | .vlans |= map(select(.id != 4001))' \
        "$SITE_FILE" > "$BATS_TEST_TMPDIR/nowan.json"
    echo "$BATS_TEST_TMPDIR/nowan.json"
}

# A copy of the site with ber1-mgmt's MAC removed, for the paths that handle a
# switch whose MAC nobody has recorded yet. Tools resolve a site by name under
# sites/, so the copy has to live there; teardown removes it.
site_without_mgmt_mac() {
    jq '(.devices[] | select(.name == "ber1-mgmt")) |= del(.mac)' "$SITE_FILE" \
        > "$FLEET_ROOT/sites/ber1-nomac.json"
}

teardown() {
    rm -f "$FLEET_ROOT/sites/ber1-nomac.json" "$FLEET_ROOT/sites/ber1-standalone.json"
}

# A subshell does not inherit the sourced library, so pipelines under `run` get
# it back this way.
fleet_sh() { bash -c "source '$FLEET_ROOT/lib/config.sh'; $1"; }

# The transcripts and the export in fixtures/ were taken off ber1-tor-b before the
# site gave its switches the edge node as gateway, before port descriptions were
# rendered, before the edges' VRRP VLAN, before the ISL was a lag and before
# the WAN ports, so they are compared with a render of the site without any of
# them.
render_as_captured() {
    jq 'del(.management.edge) | del(.vlans) | del(.devices[].lags) |
        (.devices[].ports) |= (if . then with_entries(select(.value.purpose != "wan")) else . end) |
        (.devices[].ports[]?) |= del(.description)' "$SITE_FILE" > "$BATS_TEST_TMPDIR/captured-site.json"
    fleet_render "$BATS_TEST_TMPDIR/captured-site.json" "$1"
}


# A ber1-tor-b reached over ssh that exports FAKE_CURRENT and takes a pushed
# file over TFTP, with the sudo, route and ipconfig replace runs around it.
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


# A switch that holds FAKE_BEFORE as its running configuration until a change
# has been sent to it under an armed reboot timer, then FAKE_AFTER, which is what
# the verification sees. FAKE_MEANWHILE, when set, is what it holds from its
# second read until then: somebody changed it between the read apply planned from
# and the session that applies. State lives in files because each session is its
# own ssh.
apply_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/ssh" <<'STUB'
#!/usr/bin/env bash
echo "SESSION ${*: -1}" >> "$FAKE_LOG"
sleep 0.2
printf 'sw>'
armed=0
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
        "reboot-schedule in "*) armed=1;;
        "show "*|configure|end|exit|logout|Y|"reboot-schedule cancel"|"copy running-config startup-config") ;;
        *) (( armed )) && : > "$FAKE_LOG.changed";;
    esac
    case "$line" in
        logout) exit 0;;
        "show running-config")
            reads=$(( $(cat "$FAKE_LOG.reads" 2>/dev/null || echo 0) + 1 ))
            echo "$reads" > "$FAKE_LOG.reads"
            if [ -e "$FAKE_LOG.changed" ]; then cat "$FAKE_AFTER"
            elif [ "$reads" -gt 1 ] && [ -n "${FAKE_MEANWHILE:-}" ]; then cat "$FAKE_MEANWHILE"
            else cat "$FAKE_BEFORE"; fi | sed 's/$/\r/';;
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

