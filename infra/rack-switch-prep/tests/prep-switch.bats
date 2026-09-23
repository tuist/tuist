#!/usr/bin/env bats
# Smoke tests for `mise run rack:prep-switch`.
#
#   bats infra/rack-switch-prep/tests
#
# This is the first thing that runs at a new site, on a machine that is not the
# one it was written on, sometimes by hands that have never seen it, and console
# bring-up is the step that cannot be retried cheaply from another continent. So
# everything reachable without a switch on the end of a cable is checked here:
# argument handling, the inventory lookup, and the input validation that decides
# whether the run fails in its first second or after the serial session is open.

setup_file() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
    export REPO_ROOT
    export PREP="$REPO_ROOT/mise/tasks/rack/prep-switch.sh"
}

@test "an unknown switch is refused, and says which ones exist" {
    run bash "$PREP" nonesuch --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"known switches in ber1"* ]]
    [[ "$output" == *"ber1-tor-b"* ]]
}

@test "no switch named at all is refused the same way" {
    run bash "$PREP" --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage:"* ]]
}

@test "a site that does not exist is a clear error, not a jq failure" {
    run env RACK_SITE=atlantis bash "$PREP" ber1-tor-b --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"no site definition"* ]]
}

@test "an unknown flag is refused rather than taken as the switch name" {
    run bash "$PREP" ber1-tor-b --wat
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown flag"* ]]
}

@test "each switch's dry run carries its own address from the site definition" {
    run bash "$PREP" ber1-tor-b --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"hostname ber1-tor-b"* ]]
    [[ "$output" == *"ip address 192.168.0.12 255.255.255.0"* ]]

    run bash "$PREP" ber1-tor-a --dry-run
    [[ "$output" == *"ip address 192.168.0.11 255.255.255.0"* ]]

    run bash "$PREP" ber1-mgmt --dry-run
    [[ "$output" == *"ip address 192.168.0.13 255.255.255.0"* ]]
}

@test "the dry run configures the management VLAN the site definition names" {
    vlan="$(jq -r '.management.vlan' "$REPO_ROOT/infra/rack-switch-fleet/sites/ber1.json")"
    run bash "$PREP" ber1-tor-b --dry-run
    [[ "$output" == *"interface vlan $vlan"* ]]
}

@test "the dry run ends by saving to startup, so a power cycle keeps the work" {
    run bash "$PREP" ber1-tor-b --dry-run
    [[ "$output" == *"copy running-config startup-config"* ]]
}

@test "an ed25519 key is refused before anything touches hardware" {
    # This firmware rejects ed25519. The check used to sit after the console was
    # found, 1Password read and the serial session opened, which at a new site
    # means the failure lands with someone already holding the cable.
    key="$BATS_TEST_TMPDIR/id_ed25519.pub"
    printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 someone@example\n' > "$key"
    run bash "$PREP" ber1-tor-b --dry-run --import-key "$key"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ed25519 is rejected"* ]]
    [[ "$output" != *"sudo"* ]]
}

@test "a key file that is not there is refused before anything touches hardware" {
    run bash "$PREP" ber1-tor-b --dry-run --import-key "$BATS_TEST_TMPDIR/absent.pub"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no such key file"* ]]
}

@test "an RSA key gets as far as the dry run" {
    key="$BATS_TEST_TMPDIR/id_rsa.pub"
    printf 'ssh-rsa AAAAB3NzaC1yc2E someone@example\n' > "$key"
    run bash "$PREP" ber1-tor-b --dry-run --import-key "$key"
    [ "$status" -eq 0 ]
    [[ "$output" == *"would import the key"* ]]
}

@test "the inventory is the fleet site definition, not a second copy" {
    # There used to be a switches.json next to this file. A name or an address
    # written down twice is one that will disagree with itself.
    [ ! -f "$REPO_ROOT/infra/rack-switch-prep/switches.json" ]
    run grep -c 'rack-switch-fleet/sites' "$PREP"
    [ "$output" -ge 1 ]
}
