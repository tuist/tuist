#!/usr/bin/env bats
# Zero touch: serving DHCP and TFTP to a factory switch on an isolated segment.

load helpers

# --- zero touch: serving DHCP and TFTP on an isolated segment ----------------

ztp_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/op" <<'STUB'
#!/usr/bin/env bash
cat <<'JSON'
{"fields":[{"id":"username","value":"tuist"},{"id":"password","value":"ExampleNotReal24chars000"}]}
JSON
STUB
    cat > "$dir/ipconfig" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "getifaddr" ] && { echo "${FAKE_IFADDR:-192.168.50.1}"; exit 0; }
exit 1
STUB
    cat > "$dir/ifconfig" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$dir/op" "$dir/ipconfig" "$dir/ifconfig"
    # The fleet key is found through the site definition's `~/.ssh/...` path, so a
    # HOME of our own gives the served key without touching the real one.
    mkdir -p "$dir/home/.ssh"
    ssh-keygen -q -t rsa -b 2048 -N '' -f "$dir/home/.ssh/ber1-switch-rsa"
}

@test "ztp refuses without an interface, because it is a DHCP server" {
    run "$FLEET_ROOT/ztp.sh" ber1-tor-b
    [ "$status" -ne 0 ]
    [[ "$output" == *"isolated segment"* ]]
}

@test "ztp refuses the interface carrying the default route" {
    # The guard that matters: a second DHCP server on the network people are on
    # hands addresses to their laptops.
    local default
    default="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
    [ -n "$default" ] || skip "no default route on this machine to test against"
    run "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface "$default"
    [ "$status" -ne 0 ]
    [[ "$output" == *"default route"* ]]
}

@test "ztp refuses an interface with no address" {
    bin="$BATS_TEST_TMPDIR/ztp1"
    ztp_stub "$bin"
    cat > "$bin/ipconfig" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    chmod +x "$bin/ipconfig"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0
    [ "$status" -ne 0 ]
    [[ "$output" == *"no IPv4 address"* ]]
}

@test "ztp refuses when the 1Password item has no password" {
    # A switch provisioned from scratch has none of our credentials, so a config
    # without a login would leave it unreachable.
    bin="$BATS_TEST_TMPDIR/ztp2"
    ztp_stub "$bin"
    cat > "$bin/op" <<'STUB'
#!/usr/bin/env bash
echo '{"fields":[]}'
STUB
    chmod +x "$bin/op"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"no password"* ]]
}

@test "ztp serves a config that carries a login, keyed to the switch's MAC" {
    bin="$BATS_TEST_TMPDIR/ztp3"
    ztp_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -eq 0 ]
    # DHCP only, never DNS, and bound to the one interface
    [[ "$output" == *"port=0"* ]]
    [[ "$output" == *"interface=zzz0"* ]]
    [[ "$output" == *"bind-interfaces"* ]]
    # the boot file is offered to this switch by MAC, not to whoever asks
    [[ "$output" == *"dhcp-host=d4:d6:df:03:d8:b2,set:ber1-tor-b"* ]]
    # and nothing else on the segment is answered at all
    [[ "$output" == *"dhcp-ignore=tag:!known"* ]]
    # and the TFTP server is named both ways Auto Install looks for it
    [[ "$output" == *"dhcp-option=150,192.168.50.1"* ]]
    [[ "$output" == *"67,\"ber1-tor-b.cfg\""* ]]
    # and the served file is the rendered config, with the login put back
    [[ "$output" == *'hostname "ber1-tor-b"'* ]]
    [[ "$output" == *"secret 0 <redacted>"* ]]
    # and the dry run writes nothing it should not: the password stays in 1Password
    root="$(sed -n 's/.*The files are in //p' <<<"$output")"
    run grep -rc ExampleNotReal24chars000 "$root"
    [[ "$output" != *":1"* ]]
}

# An op that knows no item until one is created, like a vault before a switch
# has ever been prepped.
ztp_empty_vault_stub() {
    local dir="$1"
    cat > "$dir/op" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
    "item get")
        [ -f "$FAKE_VAULT" ] || { echo "isn't an item" >&2; exit 1; }
        echo '{"fields":[{"id":"password","value":"GeneratedNotReal24chars0"}]}';;
    "item create") echo "CREATE $*" >> "$FAKE_VAULT.log"; touch "$FAKE_VAULT";;
esac
STUB
    chmod +x "$dir/op"
}

@test "ztp creates the 1Password item only when asked, and never in a dry run" {
    bin="$BATS_TEST_TMPDIR/ztp10"
    ztp_stub "$bin"
    ztp_empty_vault_stub "$bin"
    vault="$BATS_TEST_TMPDIR/vault"

    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_VAULT="$vault" \
        "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"--create-credentials"* ]]

    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_VAULT="$vault" \
        "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run --create-credentials
    [ "$status" -eq 0 ]
    [[ "$output" == *"a real run creates it"* ]]
    [ ! -e "$vault.log" ]

    cat > "$bin/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
    cat > "$bin/dnsmasq" <<'STUB'
#!/usr/bin/env bash
root="$(sed -n 's/^tftp-root=//p' "${1#--conf-file=}")"
cp "$root/ber1-tor-b.cfg" "$FAKE_COPY"
STUB
    chmod +x "$bin/sudo" "$bin/dnsmasq"
    copy="$BATS_TEST_TMPDIR/created.cfg"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_VAULT="$vault" FAKE_COPY="$copy" \
        "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --create-credentials < /dev/null
    [ "$status" -eq 0 ]
    run grep -c -- '--generate-password=letters,digits,24' "$vault.log"
    [ "$output" = "1" ]
    run bash -c "tr -d '\r\000' < '$copy' | grep -c 'secret 0 GeneratedNotReal24chars0$'"
    [ "$output" = "1" ]
}

@test "ztp refuses a password the switch would not accept" {
    bin="$BATS_TEST_TMPDIR/ztp8"
    ztp_stub "$bin"
    cat > "$bin/op" <<'STUB'
#!/usr/bin/env bash
echo '{"fields":[{"id":"password","value":"has a space"}]}'
STUB
    chmod +x "$bin/op"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"not one the switch accepts"* ]]
}

@test "a real run serves the password as secret 0 and deletes it once serving stops" {
    bin="$BATS_TEST_TMPDIR/ztp9"
    ztp_stub "$bin"
    cat > "$bin/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
    # dnsmasq keeps a copy of what it would have served, then stops as though
    # the operator pressed Ctrl-C.
    cat > "$bin/dnsmasq" <<'STUB'
#!/usr/bin/env bash
conf="${1#--conf-file=}"
root="$(sed -n 's/^tftp-root=//p' "$conf")"
cp "$root/ber1-tor-b.cfg" "$FAKE_COPY"
echo "$root" > "$FAKE_COPY.root"
STUB
    chmod +x "$bin/sudo" "$bin/dnsmasq"
    copy="$BATS_TEST_TMPDIR/served.cfg"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_COPY="$copy" \
        "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 < /dev/null
    [ "$status" -eq 0 ]
    run bash -c "tr -d '\r\000' < '$copy' | grep -c '^user name tuist privilege admin secret 0 ExampleNotReal24chars000$'"
    [ "$output" = "1" ]
    [ ! -e "$(cat "$copy.root")" ]
}

@test "ztp has the switch fetch the fleet key before the file moves it off this segment" {
    # Auto Install fetches only the configuration, and the key is not a
    # configuration line, so the served file has to download it. Once the file
    # reaches `interface vlan` the switch is on its site address and can no
    # longer reach this TFTP server.
    bin="$BATS_TEST_TMPDIR/ztp6"
    ztp_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -eq 0 ]
    root="$(sed -n 's/.*The files are in //p' <<<"$output")"
    served="$root/ber1-tor-b.cfg"
    download="$(tr -d '\r\000' < "$served" | grep -nx 'ip ssh download v2 fleet.pub ip-address 192.168.50.1' | cut -d: -f1)"
    address="$(tr -d '\r\000' < "$served" | grep -n '^interface vlan ' | head -1 | cut -d: -f1)"
    [ -n "$download" ]
    [ "$download" -lt "$address" ]
    run head -1 "$root/fleet.pub"
    [ "$output" = "---- BEGIN SSH2 PUBLIC KEY ----" ]
}

@test "ztp refuses an ed25519 fleet key, which the firmware rejects" {
    bin="$BATS_TEST_TMPDIR/ztp7"
    ztp_stub "$bin"
    rm -f "$bin/home/.ssh/ber1-switch-rsa" "$bin/home/.ssh/ber1-switch-rsa.pub"
    ssh-keygen -q -t ed25519 -N '' -f "$bin/home/.ssh/ber1-switch-rsa"
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"ed25519"* ]]
}

# --via: serving from a Linux machine over SSH. The ssh stub runs the remote
# command here, against an `ip` shaped like ber1-edge-a: two default routes on its
# SFP+ ports, and enp89s0 addressed on the isolated segment.
ztp_via_stub() {
    local dir="$1"
    ztp_stub "$dir"
    cat > "$dir/ssh" <<'STUB'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
    case "$1" in -o) shift 2;; -*) shift;; *) break;; esac
done
echo "SSH $1" >> "$FAKE_LOG"; shift
exec bash -c "$*"
STUB
    cat > "$dir/ip" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    "route show default")
        echo "default via 192.168.0.1 dev enp2s0f0np0 proto dhcp src 192.168.0.157 metric 100"
        echo "default via 192.168.0.1 dev enp2s0f1np1 proto dhcp src 192.168.0.158 metric 100";;
    "link show dev enp89s0"|"link show dev enp2s0f1np1") echo "5: $4: <BROADCAST,UP>";;
    "link show dev "*) exit 1;;
    "-4 -o addr show dev enp89s0")
        # the switch-side /32 first, as ber1-edge-a lists them
        echo "5: enp89s0    inet 192.168.0.10/32 scope global enp89s0"
        echo "5: enp89s0    inet 192.168.50.1/24 brd 192.168.50.255 scope global enp89s0";;
esac
STUB
    cat > "$dir/nft" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "-f" ]; then echo "NFT load $(tr -s ' \n' ' ' < "$2")" >> "$FAKE_LOG"; else echo "NFT $*" >> "$FAKE_LOG"; fi
STUB
    # Nothing listens on port 67 unless FAKE_DHCP_ACTIVE says the rack-edge pod does.
    printf '#!/bin/sh\n[ -n "$FAKE_DHCP_ACTIVE" ] && echo "UNCONN 0 0 0.0.0.0%%enp89s0:67 0.0.0.0:*"\nexit 0\n' > "$dir/ss"
    chmod +x "$dir/ssh" "$dir/ip" "$dir/nft" "$dir/ss"
    : > "$dir/log"
}

@test "--via refuses the server's default route, on any of its uplinks" {
    bin="$BATS_TEST_TMPDIR/via1"
    ztp_via_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface enp2s0f1np1 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"carries tuist@edge's default route"* ]]
    run grep -c '^SSH tuist@edge' "$bin/log"
    [ "$output" -ge 1 ]
}

@test "--via will not serve beside the rack-edge pod's DHCP for the controller path" {
    bin="$BATS_TEST_TMPDIR/via-dhcp"
    ztp_via_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" FAKE_DHCP_ACTIVE=1 \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface enp89s0 --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"already serves DHCP (the rack-edge pod"* ]]
}

@test "the edge's DHCP reply table leaves every reply but a known switch's as dnsmasq sent it" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_path "$SITE_FILE"
    [ "$status" -eq 0 ]
    chain="$(awk '/^table netdev tuist_rack_dhcp \{/ {t = 1} t && /^  chain replies \{/ {c = 1; next} c && /^  \}/ {exit} c' <<<"$output")"
    [[ "$chain" == *"type filter hook egress device \"enp87s0\" priority 0;"* ]]
    # no verdict and no policy: a provisioning lease's unicast offer to an
    # installer's MAC goes out untouched
    [[ "$chain" != *drop* ]]
    [[ "$chain" != *policy* ]]
    rules="$(grep -v 'type filter hook' <<<"$chain")"
    [ "$rules" = "    udp sport 67 udp dport 68 @th,288,48 0xa82948feb4be ether daddr set a8:29:48:fe:b4:be" ]
}

@test "the edge node hands the switches behind it their site address and their controller" {
    source "$FLEET_ROOT/lib/edge.sh"
    run fleet_edge_keepalived "$SITE_FILE" ber1-edge-a
    [[ "$output" == *"192.168.0.10/24 dev enp87s0 noprefixroute"* ]]
    run fleet_edge_path "$SITE_FILE"
    # replies to a known switch go to its MAC, since the SG3452 ignores broadcast ones
    [[ "$output" == *"udp sport 67 udp dport 68 @th,288,48 0xa82948feb4be ether daddr set a8:29:48:fe:b4:be"* ]]
    run fleet_edge_dhcp "$SITE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"interface=enp87s0"* ]]
    # the standby edge holds no address on the port, where bind-interfaces exits
    [[ "$output" == *$'\nbind-dynamic\n'* ]]
    [[ "$output" != *"bind-interfaces"* ]]
    [[ "$output" == *"dhcp-host=a8:29:48:fe:b4:be,192.168.0.13,ber1-mgmt,infinite"* ]]
    [[ "$output" == *"dhcp-option=tag:known,option:router,192.168.0.10"* ]]
    [[ "$output" == *"dhcp-range=set:provisioning,192.168.50.100,192.168.50.150,255.255.255.0,1h"* ]]
    [[ "$output" == *"dhcp-option=138,$(jq -r '.management.controller.address' "$SITE_FILE")"* ]]
    # and the ToRs, which share the management segment, are not served here
    [[ "$output" != *"dhcp-host=d4:d6:df"* ]]
}

@test "--via refuses an interface name that could smuggle a command" {
    bin="$BATS_TEST_TMPDIR/via2"
    ztp_via_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface 'enp89s0;true' --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"not an interface name"* ]]
    run cat "$bin/log"
    [ -z "$output" ]
}

@test "--via serves from the server, and removes what it copied there when it stops" {
    bin="$BATS_TEST_TMPDIR/via3"
    ztp_via_stub "$bin"
    cat > "$bin/sudo" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "-n" ] && shift
exec "$@"
STUB
    cat > "$bin/dnsmasq" <<'STUB'
#!/usr/bin/env bash
conf="${1#--conf-file=}"
root="$(sed -n 's/^tftp-root=//p' "$conf")"
cp "$root/ber1-mgmt.cfg" "$FAKE_COPY"
cp "$conf" "$FAKE_COPY.conf"
echo "$root" > "$FAKE_COPY.root"
STUB
    chmod +x "$bin/sudo" "$bin/dnsmasq"
    copy="$BATS_TEST_TMPDIR/via-served.cfg"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" FAKE_COPY="$copy" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface enp89s0 < /dev/null
    [ "$status" -eq 0 ]
    # the key comes from the server's own address on the segment
    run bash -c "tr -d '\r\000' < '$copy' | grep -c '^ip ssh download v2 fleet.pub ip-address 192.168.50.1$'"
    [ "$output" = "1" ]
    run bash -c "tr -d '\r\000' < '$copy' | grep -c '^user name tuist privilege admin secret 0 ExampleNotReal24chars000$'"
    [ "$output" = "1" ]
    # dnsmasq drops to the owner of the directory, which is the only one who can read it
    run grep -c "^user=$(id -un)$" "$copy.conf"
    [ "$output" = "1" ]
    [ ! -e "$(cat "$copy.root")" ]
    # replies go to the switch's MAC while serving, and the rule goes with it
    run grep -c "NFT load .*egress device \"enp89s0\".*ether daddr set a8:29:48:fe:b4:be" "$bin/log"
    [ "$output" = "1" ]
    run bash -c "grep -n '^NFT' '$bin/log' | tail -1"
    [[ "$output" == *"delete table netdev rack_ztp"* ]]
}

@test "--via serves from the provisioning address, not the switch-side one beside it" {
    bin="$BATS_TEST_TMPDIR/via5"
    ztp_via_stub "$bin"
    run env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface enp89s0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"at 192.168.50.1"* ]]
    [[ "$output" == *"dhcp-range=192.168.50.100,192.168.50.150,1h"* ]]
    [[ "$output" != *"dhcp-range=192.168.0."* ]]
}

@test "zero touch names the controller in option 138 once its address is known" {
    bin="$BATS_TEST_TMPDIR/via6"
    ztp_via_stub "$bin"
    copy="$BATS_TEST_TMPDIR/fleet-copy"
    cp -R "$FLEET_ROOT" "$copy"
    jq 'del(.management.controller.address)' "$FLEET_ROOT/sites/ber1.json" > "$copy/sites/ber1.json"
    run env RACK_SITE=ber1 PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" \
        "$copy/ztp.sh" ber1-mgmt --via tuist@edge --interface enp89s0 --dry-run
    [[ "$output" != *"dhcp-option=138"* ]]
    jq '.management.controller.address = "100.101.102.103"' "$FLEET_ROOT/sites/ber1.json" > "$copy/sites/ber1.json"
    run env RACK_SITE=ber1 PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" \
        "$copy/ztp.sh" ber1-mgmt --via tuist@edge --interface enp89s0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"dhcp-option=138,100.101.102.103"* ]]
}

@test "--via stops dnsmasq and removes the files on the server when this end is killed outright" {
    # What happened on ber1-edge-a: this end was killed, no trap ran, and dnsmasq
    # kept serving with the password still on disk.
    bin="$BATS_TEST_TMPDIR/via4"
    ztp_via_stub "$bin"
    cat > "$bin/sudo" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "-n" ] && shift
exec "$@"
STUB
    cat > "$bin/dnsmasq" <<'STUB'
#!/usr/bin/env bash
sed -n 's/^tftp-root=//p' "${1#--conf-file=}" > "$FAKE_STATE.root"
echo $$ > "$FAKE_STATE.pid"
exec sleep 300
STUB
    chmod +x "$bin/sudo" "$bin/dnsmasq"
    state="$BATS_TEST_TMPDIR/via4-state"
    env PATH="$bin:$PATH" HOME="$bin/home" FAKE_LOG="$bin/log" FAKE_STATE="$state" \
        "$FLEET_ROOT/ztp.sh" ber1-mgmt --via tuist@edge --interface enp89s0 < /dev/null > /dev/null 2>&1 3>&- &
    ztp=$!
    for _ in $(seq 1 50); do [ -s "$state.pid" ] && break; sleep 0.2; done
    [ -s "$state.pid" ]
    served="$(cat "$state.pid")"
    kill -9 "$ztp"
    for _ in $(seq 1 50); do
        ps -p "$served" >/dev/null 2>&1 || [ -e "$(cat "$state.root")" ] || break
        sleep 0.2
    done
    kill "$served" 2>/dev/null || true
    run ps -p "$served"
    [ "$status" -ne 0 ]
    [ ! -e "$(cat "$state.root")" ]
    run bash -c "grep -n '^NFT' '$bin/log' | tail -1"
    [[ "$output" == *"delete table netdev rack_ztp"* ]]
}

@test "ztp offers no boot file by MAC when the site definition has none" {
    bin="$BATS_TEST_TMPDIR/ztp4"
    ztp_stub "$bin"
    site_without_mgmt_mac
    run env PATH="$bin:$PATH" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" --site ber1-nomac ber1-mgmt --interface zzz0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"dhcp-boot=ber1-mgmt.cfg"* ]]
    [[ "$output" == *"no mac in the site definition"* ]]
}

@test "ztp reports a missing dnsmasq during the dry run, not after you confirm" {
    bin="$BATS_TEST_TMPDIR/ztp5"
    ztp_stub "$bin"
    # a PATH with the stubs and the basics, but deliberately no dnsmasq; yq
    # reads the RackHosts the site's machines reference
    ln -s "$(mise which yq 2>/dev/null || command -v yq)" "$bin/yq"
    run env PATH="$bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$bin/home" "$FLEET_ROOT/ztp.sh" \
        ber1-tor-b --interface zzz0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"dnsmasq"* ]]
}

