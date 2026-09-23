#!/usr/bin/env bash
#
# The rack fleet's side of the Omada controller: its Open API with client
# credentials, and the one switch-side step adoption needs.
#
#   mise run rack:omada controller         # the controller settings the switches depend on
#   mise run rack:omada devices            # what the controller sees, adopted or pending
#   mise run rack:omada inform <device>    # point a switch at the controller
#   mise run rack:omada adopt <device>     # adopt it with its own login from 1Password
#
# The controller is management.controller in the site definition. Its Open API
# client comes from the controller's first-boot wizard and lives in 1Password;
# nothing here prints a token or a password. See infra/rack-switch-fleet/AGENTS.md.

set -euo pipefail

FLEET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$FLEET_ROOT/lib/config.sh"
# shellcheck source-path=SCRIPTDIR
source "$FLEET_ROOT/lib/session.sh"

SITE="${RACK_SITE:-ber1}"
while (( $# )); do
  case "$1" in
    --site) SITE="${2:-}"; shift 2;;
    *) break;;
  esac
done
command="${1:-}"
shift || true

site_file="$(fleet_site_file "$SITE")"
[ -f "$site_file" ] || { echo "error: no site definition at $site_file" >&2; exit 2; }
url="$(jq -r '.management.controller.url // empty' "$site_file")"
site_name="$(jq -r '.management.controller.site // "Default"' "$site_file")"
api_item="$(jq -r '.management.controller.credential_item // empty' "$site_file")"
vault="$(jq -r '.credentials.vault' "$site_file")"
if [ -z "$url" ] || [ -z "$api_item" ]; then
  echo "error: $SITE has no management.controller with url and credential_item" >&2
  exit 2
fi

# The controller's certificate is its own self-signed one, reached only over
# the tailnet, whose WireGuard session is what authenticates the far end.
curl_controller() { curl -sk --max-time 30 "$@"; }

omadac_id() {
  curl_controller "$url/api/info" | jq -r '.result.omadacId // empty'
}

access_token() {
  local omadac="$1" item client_id client_secret
  item="$(op item get "$api_item" --vault "$vault" --format=json)" || {
    echo "error: 1Password did not return '$api_item'" >&2
    return 1
  }
  client_id="$(jq -r '.fields[]? | select(.label == "client-id") | .value // empty' <<<"$item")"
  client_secret="$(jq -r '.fields[]? | select(.label == "client-secret") | .value // empty' <<<"$item")"
  if [ -z "$client_id" ] || [ -z "$client_secret" ]; then
    echo "error: '$api_item' needs client-id and client-secret fields" >&2
    return 1
  fi
  jq -n --arg o "$omadac" --arg i "$client_id" --arg s "$client_secret" \
      '{omadacId: $o, client_id: $i, client_secret: $s}' |
    curl_controller -X POST -H 'Content-Type: application/json' --data @- \
      "$url/openapi/authorize/token?grant_type=client_credentials" |
    jq -r 'if .errorCode == 0 then .result.accessToken else empty end'
}

# api <method> <path under /openapi/v1/{omadacId}> [json body on stdin]
api() {
  local method="$1" path="$2" response
  if [ "$method" = GET ]; then
    response="$(curl_controller -X GET -H "Authorization: AccessToken=$TOKEN" "$url/openapi/v1/$OMADAC$path")"
  else
    response="$(curl_controller -X "$method" -H "Authorization: AccessToken=$TOKEN" \
      -H 'Content-Type: application/json' --data @- "$url/openapi/v1/$OMADAC$path")"
  fi
  if [ "$(jq -r '.errorCode // "none"' <<<"$response")" != "0" ]; then
    echo "error: $method $path: $(jq -r '.msg // "no answer"' <<<"$response" 2>/dev/null || echo "no answer")" >&2
    return 1
  fi
  printf '%s\n' "$response"
}

connect() {
  OMADAC="$(omadac_id)"
  [ -n "$OMADAC" ] || { echo "error: no Omada controller answering at $url" >&2; exit 1; }
  TOKEN="$(access_token "$OMADAC")"
  [ -n "$TOKEN" ] || { echo "error: the controller refused the Open API client in '$api_item'" >&2; exit 1; }
  local sites
  sites="$(api GET "/sites?page=1&pageSize=100")" || exit 1
  SITE_ID="$(jq -r --arg n "$site_name" '.result.data[] | select(.name == $n) | .siteId' <<<"$sites")"
  if [ -z "$SITE_ID" ]; then
    echo "error: the controller has no site named '$site_name'; it has: $(jq -r '[.result.data[].name] | join(", ")' <<<"$sites")" >&2
    exit 1
  fi
}

# The controller writes MACs upper case with dashes.
controller_mac() { tr 'a-f:' 'A-F-' <<<"$1"; }

# A device's detailStatus, or its coarse status prefixed with "s" when the
# controller gives no detail.
device_state() {
  case "$1" in
    0|s0) echo "disconnected";;
    1) echo "disconnected (migrating)";;
    10) echo "provisioning";;
    11) echo "configuring";;
    12) echo "upgrading";;
    13) echo "rebooting";;
    14|s1) echo "connected";;
    16) echo "connected (migrating)";;
    20|s2) echo "pending";;
    22) echo "adopting";;
    24) echo "adoption failed";;
    26) echo "managed by another controller";;
    30|s3) echo "heartbeat missed";;
    40|s4) echo "isolated";;
    *) echo "status $1";;
  esac
}

device_field() {
  jq -r --arg n "$2" --arg f "$1" '.devices[] | select(.name == $n) | .[$f] // empty' "$site_file"
}

controller_address() {
  local address
  address="$(jq -r '.management.controller.address // empty' "$site_file")"
  if [ -z "$address" ]; then
    echo "error: set management.controller.address to the controller's tailnet IP first;" >&2
    echo "       a switch has no resolver for MagicDNS names" >&2
    exit 2
  fi
  echo "$address"
}

# An adopted switch connects back to the address the controller advertises for
# device management. It starts unset, and the switches reach the controller only
# at its tailnet address.
ensure_device_host() {
  local address current
  address="$(controller_address)" || exit 2
  current="$(api GET "/controller/setting/general" |
    jq -r 'if .result.deviceManage.deviceHostEnable then .result.deviceManage.deviceHost else "" end')" || exit 1
  [ "$current" = "$address" ] && return 0
  jq -n --arg a "$address" '{deviceManage: {deviceHostEnable: true, deviceHost: $a}}' |
    api PATCH "/controller/setting/general" >/dev/null || exit 1
  echo "the controller now tells switches to connect back to $address${current:+ (was $current)}"
}

# The controller pushes its site's SSH setting to every switch it adopts, and
# the setting starts disabled: ber1-mgmt refused SSH once adopted. The fleet
# reads and verifies over SSH, so the site keeps it on.
ensure_site_ssh() {
  local current
  current="$(api GET "/sites/$SITE_ID/ssh")" || exit 1
  if jq -e '.result.sshEnable == true and .result.sshServerPort == 22' <<<"$current" >/dev/null; then
    return 0
  fi
  jq '.result | .sshEnable = true | .sshServerPort = 22' <<<"$current" |
    api PUT "/sites/$SITE_ID/ssh" >/dev/null || exit 1
  echo "the controller now keeps SSH on for the switches in $site_name"
}

# Controller settings the switches depend on, from the site definition.
converge_controller() {
  ensure_device_host
  ensure_site_ssh
}

case "$command" in
  controller)
    connect
    converge_controller
    echo "controller $url matches the site definition for $SITE"
    ;;

  devices)
    connect
    names="$(jq -c '[.devices[] | select(.mac) | {key: (.mac | ascii_upcase | gsub(":"; "-")), value: .name}] | from_entries' "$site_file")"
    echo "controller $url, site $site_name"
    # The site's device list carries pending switches as well as adopted ones.
    api GET "/sites/$SITE_ID/devices?page=1&pageSize=100" |
      jq -r --argjson names "$names" '.result.data[] |
        [.mac, (.ip // "-"), (.model // "-"), ($names[.mac] // "(not in the site)"),
         (if .detailStatus != null then .detailStatus else "s\(.status)" end | tostring)] | @tsv' |
      while IFS=$'\t' read -r mac ip model device state; do
        printf '  %-18s %-16s %-24s %-12s %s\n' "$mac" "$ip" "$model" "$device" "$(device_state "$state")"
      done
    ;;

  inform)
    name="${1:-}"
    [ -n "$name" ] || { echo "usage: rack:omada inform <device>" >&2; exit 2; }
    address="$(controller_address)" || exit 2
    switch_address="$(device_field mgmt_address "$name")"
    [ -n "$switch_address" ] || { echo "error: $name is not in $SITE" >&2; exit 1; }
    fleet_load_jumps "$site_file"
    (
      trap switch_close EXIT
      switch_open "$switch_address" "$(jq -r '.credentials.username' "$site_file")" \
        "$(jq -r '.credentials.ssh_key' "$site_file")" || exit 1
      switch_run "configure" || exit 1
      switch_run "controller inform-url $address" || exit 1
      switch_run "end" || exit 1
    )
    echo "$name now informs $address. Running configuration only: adopting it hands its"
    echo "configuration to the controller, and a reboot before that forgets the pointer."
    ;;

  adopt)
    name="${1:-}"
    [ -n "$name" ] || { echo "usage: rack:omada adopt <device>" >&2; exit 2; }
    mac="$(device_field mac "$name")"
    [ -n "$mac" ] || { echo "error: $name has no mac in $SITE, which is how the controller knows it" >&2; exit 1; }
    mac="$(controller_mac "$mac")"
    connect
    converge_controller
    if ! api GET "/sites/$SITE_ID/grid/devices/pending?page=1&pageSize=100" |
        jq -e --arg m "$mac" '.result.data[] | select(.mac == $m)' >/dev/null; then
      echo "error: $name ($mac) is not pending on the controller; rack:omada inform it first" >&2
      exit 1
    fi
    switch_item="$(device_field credential_item "$name")"
    switch_login="$(op item get "$switch_item" --vault "$vault" --format=json)" || {
      echo "error: 1Password did not return '$switch_item'" >&2
      exit 1
    }
    jq -c '{username: (.fields[] | select(.id == "username") | .value),
            password: (.fields[] | select(.id == "password") | .value)}' <<<"$switch_login" |
      api POST "/sites/$SITE_ID/devices/$mac/start-adopt" >/dev/null
    echo "adopting $name ($mac); waiting for it to connect"
    # A failure from an earlier attempt, the setup wizard's included, stays on
    # the device until the controller picks this request up, so a failure only
    # counts once the device has shown some other state.
    moved=0
    state=""
    for _ in $(seq 1 60); do
      device="$(api GET "/sites/$SITE_ID/devices?page=1&pageSize=100" |
        jq -c --arg m "$mac" '.result.data[] | select(.mac == $m)' || true)"
      if [ "$(jq -r '.status // empty' <<<"$device")" = "1" ]; then
        echo "$name is adopted and connected"
        exit 0
      fi
      state="$(jq -r '.detailStatus // empty' <<<"$device")"
      case "$state" in
        24) if (( moved )); then
              echo "error: the controller reports adopting $name failed; check the login in '$switch_item'" >&2
              exit 1
            fi;;
        26) echo "error: $name is managed by another controller" >&2; exit 1;;
        *) moved=1;;
      esac
      sleep 5
    done
    echo "error: $name did not show as connected within five minutes; last state: $(device_state "${state:-unknown}")" >&2
    exit 1
    ;;

  *)
    echo "usage: mise run rack:omada <controller|devices|inform|adopt> [device]" >&2
    exit 2
    ;;
esac
