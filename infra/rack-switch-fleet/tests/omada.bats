#!/usr/bin/env bats
# The Omada controller's Open API, against a fake controller.

load helpers

# --- the Omada controller's Open API -----------------------------------------

# A controller behind curl: one site, ber1, whose device list is FAKE_DEVICES
# (pending switches included, as on the real one) and whose pending list is
# FAKE_PENDING. The adoption request body is kept to check what was sent.
omada_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/curl" <<'STUB'
#!/usr/bin/env bash
method=GET; url=""; body=""
while [ $# -gt 0 ]; do
    case "$1" in
        -X) method="$2"; shift 2;;
        --data) [ "$2" = "@-" ] && body="$(cat)"; shift 2;;
        -H|--max-time) shift 2;;
        -*) shift;;
        *) url="$1"; shift;;
    esac
done
empty='{"errorCode":0,"result":{"data":[]}}'
pending="${FAKE_PENDING:-$empty}"
devices="${FAKE_DEVICES:-$empty}"
unset_host='{"errorCode":0,"result":{"deviceManage":null}}'
general="${FAKE_GENERAL:-$unset_host}"
ssh_off='{"errorCode":0,"result":{"sshEnable":false,"sshServerPort":22,"layer3Access":false}}'
ssh="${FAKE_SSH:-$ssh_off}"
wizard_account='{"errorCode":0,"result":{"username":"admin","password":"WizardSet1!"}}'
account="${FAKE_ACCOUNT:-$wizard_account}"
mac_named='{"errorCode":0,"result":{"name":"A8-29-48-FE-B4-BE"}}'
switch_general="${FAKE_SWITCH_GENERAL:-$mac_named}"
two_ports='{"errorCode":0,"result":{"portList":[{"port":1,"name":"Port1","profileId":"P"},{"port":52,"name":"api-write-test","profileId":"P"}]}}'
switch="${FAKE_SWITCH:-$two_ports}"
echo "$method $url" >> "$FAKE_LOG"
case "$url" in
    */api/info) echo '{"result":{"omadacId":"OMC"}}';;
    */openapi/authorize/token*)
        if [ -n "${FAKE_REFUSE:-}" ]; then echo '{"errorCode":-44106,"msg":"Invalid client"}'
        else echo '{"errorCode":0,"result":{"accessToken":"AT-1"}}'; fi;;
    */sites\?page*) echo '{"errorCode":0,"result":{"data":[{"name":"ber1","siteId":"S1"}]}}';;
    */grid/devices/pending*) echo "$pending";;
    */devices\?page*)
        # One document per line, one per call, the last repeating.
        n=$(( $(cat "$FAKE_LOG.polls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_LOG.polls"
        line="$(printf '%s\n' "$devices" | sed -n "${n}p")"
        [ -n "$line" ] || line="$(printf '%s\n' "$devices" | tail -1)"
        echo "$line";;
    */start-adopt) printf '%s' "$body" > "$FAKE_LOG.adopt"; echo '{"errorCode":0}';;
    */controller/setting/general)
        if [ "$method" = GET ]; then echo "$general"
        else printf '%s' "$body" > "$FAKE_LOG.general"; echo '{"errorCode":0}'; fi;;
    */sites/S1/ssh)
        if [ "$method" = GET ]; then echo "$ssh"
        else printf '%s' "$body" > "$FAKE_LOG.ssh"; echo '{"errorCode":0}'; fi;;
    */switches/A8-29-48-FE-B4-BE/general-config)
        if [ "$method" = GET ]; then echo "$switch_general"
        else printf '%s %s %s\n' "$method" "${url#*/sites/S1/}" "$body" >> "$FAKE_LOG.writes"; echo '{"errorCode":0}'; fi;;
    */switches/A8-29-48-FE-B4-BE/ports/*|*/switches/A8-29-48-FE-B4-BE/config/loopback)
        printf '%s %s %s\n' "$method" "${url#*/sites/S1/}" "$body" >> "$FAKE_LOG.writes"; echo '{"errorCode":0}';;
    */switches/A8-29-48-FE-B4-BE) echo "$switch";;
    */sites/S1/device-account)
        if [ "$method" = GET ]; then echo "$account"
        else printf '%s' "$body" > "$FAKE_LOG.account-put"; echo '{"errorCode":0}'; fi;;
    *) echo '{"errorCode":-1,"msg":"unexpected"}';;
esac
STUB
    # The device account item holds whatever password is in log.account; create
    # and edit take the next of FAKE_GENERATED's lines, the last repeating.
    cat > "$dir/op" <<'STUB'
#!/usr/bin/env bash
case "$2 $3" in
    "get omada production open api")
        echo '{"fields":[{"label":"client-id","value":"cid"},{"label":"client-secret","value":"csecret"}]}';;
    "get ber1 switch device account")
        [ -f "$FAKE_LOG.account" ] || { echo '"ber1 switch device account" isn'"'"'t an item' >&2; exit 1; }
        jq -n --rawfile p "$FAKE_LOG.account" '{fields: [{id: "username", value: "tuist"}, {id: "password", value: ($p | rtrimstr("\n"))}]}';;
    create*|edit*)
        echo "$*" >> "$FAKE_LOG.op"
        n=$(( $(cat "$FAKE_LOG.generated" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_LOG.generated"
        printf '%s\n' "${FAKE_GENERATED:-Rk7#mQ2x!vL9pZ4w}" | sed -n "${n}p;\$p" | head -1 > "$FAKE_LOG.account";;
    *)
        echo '{"fields":[{"id":"username","value":"tuist"},{"id":"password","value":"SwitchNotReal24chars0000"}]}';;
esac
STUB
    echo 'Rk7#mQ2x!vL9pZ4w' > "$dir/log.account"
    printf '#!/bin/sh\n:\n' > "$dir/sleep"
    chmod +x "$dir/curl" "$dir/op" "$dir/sleep"
    : > "$dir/log"
}

@test "adoption refuses a switch the controller does not list as pending" {
    bin="$BATS_TEST_TMPDIR/omada1"
    omada_stub "$bin"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" "$FLEET_ROOT/omada.sh" adopt ber1-mgmt
    [ "$status" -ne 0 ]
    [[ "$output" == *"not pending"* ]]
    [ ! -e "$bin/log.adopt" ]
}

@test "adoption sends the switch's own login for its MAC, and prints neither secret" {
    bin="$BATS_TEST_TMPDIR/omada2"
    omada_stub "$bin"
    pending='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","ip":"192.168.0.13","status":0}]}}'
    devices='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","status":1,"detailStatus":14}]}}'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_PENDING="$pending" FAKE_DEVICES="$devices" \
        "$FLEET_ROOT/omada.sh" adopt ber1-mgmt
    [ "$status" -eq 0 ]
    [[ "$output" == *"adopted and connected"* ]]
    run grep -c "POST $(jq -r '.management.controller.url' "$SITE_FILE")/openapi/v1/OMC/sites/S1/devices/A8-29-48-FE-B4-BE/start-adopt" "$bin/log"
    [ "$output" = "1" ]
    run jq -r '"\(.username) \(.password)"' "$bin/log.adopt"
    [ "$output" = "tuist SwitchNotReal24chars0000" ]
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_PENDING="$pending" FAKE_DEVICES="$devices" \
        "$FLEET_ROOT/omada.sh" adopt ber1-mgmt
    [[ "$output" != *"SwitchNotReal24chars0000"* ]]
    [[ "$output" != *"csecret"* ]]
    [[ "$output" != *"AT-1"* ]]
}

@test "the controller's devices are named from the site definition" {
    bin="$BATS_TEST_TMPDIR/omada3"
    omada_stub "$bin"
    devices='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","ip":"192.168.0.13","model":"SG3452 v1.30","status":2,"detailStatus":20},{"mac":"00-11-22-33-44-55","ip":"192.168.0.99","model":"SG3428 v2","status":1}]}}'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_DEVICES="$devices" "$FLEET_ROOT/omada.sh" devices
    [ "$status" -eq 0 ]
    [[ "$output" == *"A8-29-48-FE-B4-BE"*"ber1-mgmt"*"pending"* ]]
    [[ "$output" == *"00-11-22-33-44-55"*"(not in the site)"*"connected"* ]]
    [ "$(grep -c 'A8-29-48-FE-B4-BE' <<<"$output")" -eq 1 ]
}

@test "adoption stops as soon as the controller reports it failed" {
    bin="$BATS_TEST_TMPDIR/omada5"
    omada_stub "$bin"
    pending='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","ip":"192.168.0.13","status":2}]}}'
    devices='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","status":2,"detailStatus":22}]}}
{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","status":2,"detailStatus":24}]}}'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_PENDING="$pending" FAKE_DEVICES="$devices" \
        "$FLEET_ROOT/omada.sh" adopt ber1-mgmt
    [ "$status" -eq 1 ]
    [[ "$output" == *"adopting ber1-mgmt failed; check the login in 'ber1-mgmt switch admin'"* ]]
    [ "$(cat "$bin/log.polls")" -eq 2 ]
}

@test "adoption first has the controller advertise the address switches reach it at" {
    # The setting starts unset on a new controller, and the switches reach it
    # only at its tailnet address.
    bin="$BATS_TEST_TMPDIR/omada7"
    omada_stub "$bin"
    pending='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","ip":"192.168.0.13","status":2}]}}'
    devices='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","status":1,"detailStatus":14}]}}'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_PENDING="$pending" FAKE_DEVICES="$devices" \
        "$FLEET_ROOT/omada.sh" adopt ber1-mgmt
    [ "$status" -eq 0 ]
    address="$(jq -r '.management.controller.address' "$SITE_FILE")"
    [[ "$output" == *"connect back to $address"* ]]
    run jq -c '.deviceManage' "$bin/log.general"
    [ "$output" = "{\"deviceHostEnable\":true,\"deviceHost\":\"$address\"}" ]
}

@test "adoption leaves the advertised address alone when it is already right" {
    bin="$BATS_TEST_TMPDIR/omada8"
    omada_stub "$bin"
    address="$(jq -r '.management.controller.address' "$SITE_FILE")"
    general="{\"errorCode\":0,\"result\":{\"deviceManage\":{\"deviceHostEnable\":true,\"deviceHost\":\"$address\"}}}"
    pending='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","ip":"192.168.0.13","status":2}]}}'
    devices='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","status":1,"detailStatus":14}]}}'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_PENDING="$pending" FAKE_DEVICES="$devices" FAKE_GENERAL="$general" \
        "$FLEET_ROOT/omada.sh" adopt ber1-mgmt
    [ "$status" -eq 0 ]
    [[ "$output" != *"connect back"* ]]
    [ ! -e "$bin/log.general" ]
}

@test "the controller keeps SSH on for the site's switches, since the fleet verifies over it" {
    # Adopted under the site's default, ber1-mgmt refused SSH.
    bin="$BATS_TEST_TMPDIR/omada9"
    omada_stub "$bin"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" "$FLEET_ROOT/omada.sh" controller
    [ "$status" -eq 0 ]
    [[ "$output" == *"keeps SSH on for the switches in ber1"* ]]
    run jq -c . "$bin/log.ssh"
    [ "$output" = '{"sshEnable":true,"sshServerPort":22,"layer3Access":false}' ]
}

@test "the controller command changes nothing that already matches" {
    bin="$BATS_TEST_TMPDIR/omada10"
    omada_stub "$bin"
    address="$(jq -r '.management.controller.address' "$SITE_FILE")"
    general="{\"errorCode\":0,\"result\":{\"deviceManage\":{\"deviceHostEnable\":true,\"deviceHost\":\"$address\"}}}"
    ssh='{"errorCode":0,"result":{"sshEnable":true,"sshServerPort":22,"layer3Access":false}}'
    account='{"errorCode":0,"result":{"username":"tuist","password":"Rk7#mQ2x!vL9pZ4w"}}'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_GENERAL="$general" FAKE_SSH="$ssh" FAKE_ACCOUNT="$account" \
        "$FLEET_ROOT/omada.sh" controller
    [ "$status" -eq 0 ]
    [[ "$output" == *"matches the site definition for ber1"* ]]
    [ ! -e "$bin/log.general" ]
    [ ! -e "$bin/log.ssh" ]
    [ ! -e "$bin/log.account-put" ]
}

@test "the controller's device account is the one in 1Password, and neither is printed" {
    bin="$BATS_TEST_TMPDIR/omada11"
    omada_stub "$bin"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" "$FLEET_ROOT/omada.sh" controller
    [ "$status" -eq 0 ]
    [[ "$output" == *"gives the switches in ber1 the login in 'ber1 switch device account'"* ]]
    [[ "$output" != *'Rk7#mQ2x!vL9pZ4w'* ]]
    [[ "$output" != *"WizardSet1!"* ]]
    run jq -r '"\(.username) \(.password)"' "$bin/log.account-put"
    [ "$output" = 'tuist Rk7#mQ2x!vL9pZ4w' ]
}

@test "a missing device account item is created only when asked" {
    bin="$BATS_TEST_TMPDIR/omada12"
    omada_stub "$bin"
    rm "$bin/log.account"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" "$FLEET_ROOT/omada.sh" controller
    [ "$status" -ne 0 ]
    [[ "$output" == *"no 1Password item 'ber1 switch device account'; --create-device-account makes one"* ]]
    [ ! -e "$bin/log.op" ]
    [ ! -e "$bin/log.account-put" ]
}

@test "a created device account is regenerated until both the controller and the switch accept it" {
    # 1Password's generator can repeat a character, add a question mark or leave
    # out a symbol; the controller rejects all three, the switch the second.
    bin="$BATS_TEST_TMPDIR/omada13"
    omada_stub "$bin"
    rm "$bin/log.account"
    generated='Rk7#mQ2xx!vL9pZ4w
Rk7#mQ2x?vL9pZ4w
Rk7mQ2xAvL9pZ4wB
Tq3!nW8e#Yb5Lc2V'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_GENERATED="$generated" \
        "$FLEET_ROOT/omada.sh" controller --create-device-account
    [ "$status" -eq 0 ]
    [[ "$output" == *"created the 1Password item 'ber1 switch device account'"* ]]
    run grep -c '^item create ' "$bin/log.op"
    [ "$output" = "1" ]
    run grep -c '^item edit ' "$bin/log.op"
    [ "$output" = "3" ]
    run grep -c 'username=tuist' "$bin/log.op"
    [ "$output" = "1" ]
    run jq -r '"\(.username) \(.password)"' "$bin/log.account-put"
    [ "$output" = 'tuist Tq3!nW8e#Yb5Lc2V' ]
}

@test "an adopted switch's render goes through the Open API, and only what differs is written" {
    bin="$BATS_TEST_TMPDIR/omada14"
    omada_stub "$bin"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" "$FLEET_ROOT/omada.sh" apply ber1-mgmt
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/rack-fleet-ber1.lock" ]
    [[ "$output" == *"hostname: A8-29-48-FE-B4-BE -> ber1-mgmt"* ]]
    [[ "$output" == *"port 52: api-write-test -> Port52"* ]]
    [[ "$output" != *"port 1:"* ]]
    run grep -c '' "$bin/log.writes"
    [ "$output" = "3" ]
    run grep -F 'PATCH switches/A8-29-48-FE-B4-BE/general-config {"name":"ber1-mgmt"}' "$bin/log.writes"
    [ "$status" -eq 0 ]
    run grep -F 'PATCH switches/A8-29-48-FE-B4-BE/ports/52 {"name":"Port52","profileId":"P"}' "$bin/log.writes"
    [ "$status" -eq 0 ]
    run bash -c "grep '^PUT switches/A8-29-48-FE-B4-BE/config/loopback ' '$bin/log.writes' | cut -d' ' -f3- | jq -c '{stp, loopbackDetectEnable}'"
    [ "$output" = '{"stp":2,"loopbackDetectEnable":true}' ]
}

@test "the Open API path waits out a ToR's pending rollback like every other change" {
    bin="$BATS_TEST_TMPDIR/omada16"
    omada_stub "$bin"
    now="$(date +%s)"
    printf 'device ber1-tor-b\naddress 192.168.0.12\narmed %s\nfires %s\n' "$now" "$(( now + 300 ))" \
        > "$BATS_TEST_TMPDIR/rack-fleet-ber1.rollback"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FLEET_LOCK_DIR="$BATS_TEST_TMPDIR" "$FLEET_ROOT/omada.sh" apply ber1-mgmt
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-tor-b may still be rolling back"* ]]
    [ ! -e "$bin/log.writes" ]
    [ ! -e "$BATS_TEST_TMPDIR/rack-fleet-ber1.lock" ]
}

@test "the Open API path is only for a switch the controller has adopted" {
    bin="$BATS_TEST_TMPDIR/omada15"
    omada_stub "$bin"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" "$FLEET_ROOT/omada.sh" apply ber1-tor-b
    [ "$status" -eq 1 ]
    [[ "$output" == *"ber1-tor-b is not adopted; a standalone switch changes with rack:fleet apply"* ]]
    [ ! -e "$bin/log.writes" ]
}

@test "a failure left over from an earlier attempt does not end a new adoption" {
    # The setup wizard tried ber1-mgmt with the factory login, and the device
    # still read "adoption failed" when rack:omada adopt started.
    bin="$BATS_TEST_TMPDIR/omada6"
    omada_stub "$bin"
    pending='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","ip":"192.168.0.13","status":2}]}}'
    devices='{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","status":2,"detailStatus":24}]}}
{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","status":2,"detailStatus":22}]}}
{"errorCode":0,"result":{"data":[{"mac":"A8-29-48-FE-B4-BE","status":1,"detailStatus":14}]}}'
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_PENDING="$pending" FAKE_DEVICES="$devices" \
        "$FLEET_ROOT/omada.sh" adopt ber1-mgmt
    [ "$status" -eq 0 ]
    [[ "$output" == *"adopted and connected"* ]]
}

@test "a refused Open API client says which 1Password item it came from" {
    bin="$BATS_TEST_TMPDIR/omada4"
    omada_stub "$bin"
    run env PATH="$bin:$PATH" FAKE_LOG="$bin/log" FAKE_REFUSE=1 "$FLEET_ROOT/omada.sh" devices
    [ "$status" -ne 0 ]
    [[ "$output" == *"refused the Open API client in 'omada production open api'"* ]]
}

@test "inform needs the controller's tailnet address, since a switch cannot resolve its name" {
    copy="$BATS_TEST_TMPDIR/fleet-copy"
    cp -R "$FLEET_ROOT" "$copy"
    jq 'del(.management.controller.address)' "$FLEET_ROOT/sites/ber1.json" > "$copy/sites/ber1.json"
    run env RACK_SITE=ber1 "$copy/omada.sh" inform ber1-mgmt
    [ "$status" -eq 2 ]
    [[ "$output" == *"management.controller.address"* ]]
}
