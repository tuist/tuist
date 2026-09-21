#!/usr/bin/env bash
#MISE description="Prepare a BER1 rack switch over its USB-C console (hostname, management IP, SSH, fleet key)"
#
# A factory TP-Link switch ships on 192.168.0.1 with SSH disabled, which is the
# gateway address of most networks it is ever unboxed on: the unit collides with
# the router the moment it is plugged in, and the collision is invisible, so
# configuring it over the network means isolating it first. The console port has
# none of that. It needs no addressing, it works when the config is broken, and
# it is how remote hands will recover a switch in the colo.
#
# This names the switch, gives it the fixed management address from
# infra/rack-switch-fleet/sites/<site>.json, enables SSH, saves to startup config and
# reads the device back to verify. It handles a factory-fresh unit and an
# already-configured one, so re-running it converges.
#
# Connect a USB-C cable from this machine to the switch's console port first.
#
# Usage:
#   mise run rack:prep-switch <switch> [--import-key <pubkey>] [--dry-run] [--verbose]
#   e.g. mise run rack:prep-switch ber1-tor-a
#        mise run rack:prep-switch ber1-mgmt --create-credentials
#        mise run rack:prep-switch ber1-tor-a --import-key ~/.ssh/ber1-switch-rsa.pub
#
# The admin login comes from the 1Password item named in the site definition (account
# override: OP_ACCOUNT); --create-credentials generates it on a switch's first
# run. --import-key installs the fleet SSH key so the switch can be driven
# without a password afterwards: the switch fetches it over TFTP from this
# machine, which needs sudo because TFTP is always served on port 69.
#
# See infra/rack-switch-prep/AGENTS.md for what is deliberately left to a fleet
# change, and for the console baud rate and firmware-line traps.

set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "error: needs bash 4+ (macOS /bin/bash is 3.2); run through mise or install bash" >&2
  exit 1
fi

switch=""
key_path=""
device=""
baud=38400
dry_run=0
verbose=0
create_credentials=0

while (( $# )); do
  case "$1" in
    --import-key) key_path="${2:-}"; shift 2;;
    --device) device="${2:-}"; shift 2;;
    --baud) baud="${2:-}"; shift 2;;
    --dry-run) dry_run=1; shift;;
    --verbose) verbose=1; shift;;
    --create-credentials) create_credentials=1; shift;;
    -*) echo "unknown flag: $1" >&2; exit 2;;
    *) switch="$1"; shift;;
  esac
done

root="$(git rev-parse --show-toplevel)"
site="${RACK_SITE:-ber1}"
inventory="$root/infra/rack-switch-fleet/sites/$site.json"

if [ ! -f "$inventory" ]; then
  echo "error: no site definition at $inventory" >&2
  exit 2
fi

if [ -z "$switch" ] || ! jq -e --arg s "$switch" '.devices[] | select(.name == $s)' "$inventory" >/dev/null; then
  echo "usage: mise run rack:prep-switch <switch> [flags]" >&2
  echo "known switches in $site: $(jq -r '[.devices[].name] | join(", ")' "$inventory")" >&2
  exit 2
fi

entry="$(jq -r --arg s "$switch" '.devices[] | select(.name == $s)' "$inventory")"
model="$(jq -r '.model' <<<"$entry")"
mgmt_ip="$(jq -r '.mgmt_address' <<<"$entry")"
mgmt_mask="$(jq -r '.management.netmask' "$inventory")"
mgmt_vlan="$(jq -r '.management.vlan' "$inventory")"
credential_item="$(jq -r '.credential_item' <<<"$entry")"
vault="$(jq -r '.credentials.vault' "$inventory")"

commands=(
  "configure"
  "hostname $switch"
  "interface vlan $mgmt_vlan"
  "ip address $mgmt_ip $mgmt_mask"
  "exit"
  "ip ssh server"
  "end"
  "copy running-config startup-config"
)

if (( dry_run )); then
  echo "would apply to $switch ($model):"
  printf '  %s\n' "${commands[@]}"
  exit 0
fi

if [ -z "$device" ]; then
  mapfile -t candidates < <(ls /dev/cu.usbmodem* 2>/dev/null || true)
  if (( ${#candidates[@]} == 0 )); then
    echo "error: no USB console found. Connect a USB-C cable to the switch's console port." >&2
    exit 1
  fi
  if (( ${#candidates[@]} > 1 )); then
    echo "error: several USB consoles present, pick one with --device: ${candidates[*]}" >&2
    exit 1
  fi
  device="${candidates[0]}"
fi

op_args=(item get "$credential_item" --vault "$vault" --format=json)
[ -n "${OP_ACCOUNT:-}" ] && op_args+=(--account "$OP_ACCOUNT")

if ! credentials="$(op "${op_args[@]}" 2>/dev/null)"; then
  if (( ! create_credentials )); then
    echo "error: 1Password item '$credential_item' not found in vault $vault." >&2
    echo "       pass --create-credentials to generate it" >&2
    exit 1
  fi
  # shellcheck disable=SC2054  # commas belong to op's own flag values
  create_args=(item create --category=login "--title=$credential_item" --vault "$vault"
               --generate-password=letters,digits,24 --tags=ber1,rack,network username=tuist)
  [ -n "${OP_ACCOUNT:-}" ] && create_args+=(--account "$OP_ACCOUNT")
  op "${create_args[@]}" >/dev/null
  credentials="$(op "${op_args[@]}")"
fi

username="$(jq -r '.fields[] | select(.id=="username") | .value' <<<"$credentials")"
password="$(jq -r '.fields[] | select(.id=="password") | .value' <<<"$credentials")"

if [ -z "$username" ] || [ -z "$password" ]; then
  echo "error: 1Password item '$credential_item' has no username/password" >&2
  exit 1
fi

tftp_started=0
served_file=""

cleanup() {
  exec 3<&- 2>/dev/null || true
  if (( tftp_started )); then
    sudo -n launchctl bootout system/com.apple.tftpd 2>/dev/null || true
  fi
  if [ -n "$served_file" ]; then
    sudo -n rm -f "$served_file" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Opening the port resets its line settings, so configure the descriptor we hold
# rather than the device path, or everything reads back as noise.
exec 3<>"$device"
stty "$baud" cs8 -cstopb -parenb raw -echo <&3
echo "console $device at $baud baud"

CONSOLE_OUT=""

# Idle is counted in 0.2s read timeouts; the limit is wall clock, because a long
# `show` is thousands of reads and must not be mistaken for a stalled session.
console_read() {
  local idle_ticks="$1" limit_seconds="$2" want_prompt="$3"
  local buf="" ch quiet=0 start=$SECONDS
  while (( SECONDS - start < limit_seconds )); do
    if IFS= read -r -N 1 -t 0.2 ch <&3; then
      buf+="$ch"
      quiet=0
      case "$buf" in
        *"Press any key to continue"*|*"--More--"*)
          printf ' ' >&3
          buf="${buf//Press any key to continue (Q to quit)/}"
          ;;
      esac
      continue
    fi
    (( quiet++ )) || true
    if (( quiet >= idle_ticks )); then
      if (( want_prompt )); then
        # This CLI echoes a command long before it runs it, so silence alone is
        # not a turn boundary: wait for the prompt to come back.
        if [[ "$buf" =~ [A-Za-z0-9._-]+(\([a-z-]+\))?[\>#][[:space:]]*$ ]]; then
          break
        fi
      else
        break
      fi
    fi
  done
  CONSOLE_OUT="${buf//$'\r'/}"
  if (( verbose )) && [ -n "${CONSOLE_OUT//[[:space:]]/}" ]; then
    printf '%s\n' "$CONSOLE_OUT" >&2
  fi
}

console_send() {
  local text="$1" idle="${2:-5}" limit="${3:-45}" want_prompt="${4:-1}" secret="${5:-0}" i
  if (( verbose )); then
    if (( secret )); then echo ">>> ********" >&2; else echo ">>> $text" >&2; fi
  fi
  for (( i = 0; i < ${#text}; i++ )); do
    printf '%s' "${text:i:1}" >&3
    sleep 0.02
  done
  sleep 0.3
  printf '\r' >&3
  console_read "$idle" "$limit" "$want_prompt"
}

console_send "" 10 15 0
banner="$CONSOLE_OUT"

case "$banner" in
  *"Set now"*|*"set an administrator account"*)
    console_send "Y" 10 15 0
    console_send "$username" 10 15 0
    console_send "$password" 10 15 0 1
    console_send "$password" 15 20 0 1
    banner="$CONSOLE_OUT"
    ;;
esac

case "$banner" in
  *"User:"*|*"Username:"*|*"Login invalid"*)
    console_send "$username" 10 15 0
    console_send "$password" 15 20 0 1
    banner="$CONSOLE_OUT"
    ;;
esac

case "$banner" in
  *"Login invalid"*)
    echo "error: the switch rejected the stored credentials. Update the 1Password" >&2
    echo "       item, or factory-reset the switch." >&2
    exit 1
    ;;
esac

case "$banner" in
  *"#"*) ;;
  *) console_send "enable" 10 20 1; banner="$CONSOLE_OUT";;
esac

case "$banner" in
  *"#"*) ;;
  *)
    echo "error: could not reach a privileged prompt:" >&2
    echo "$banner" >&2
    exit 1
    ;;
esac

# A session left in configuration mode by an earlier run rejects `configure`.
for _ in 1 2 3 4; do
  case "$banner" in
    *"(config"*) console_send "end" 5 15 1; banner="$CONSOLE_OUT";;
    *) break;;
  esac
done

for command in "${commands[@]}"; do
  case "$command" in
    copy*) console_send "$command" 30 120 1;;
    *) console_send "$command" 5 45 1;;
  esac
  case "$CONSOLE_OUT" in
    *"Bad command"*|*"Invalid"*|*"Error"*)
      echo "error: switch rejected '$command':" >&2
      echo "$CONSOLE_OUT" >&2
      exit 1
      ;;
  esac
done

if [ -n "$key_path" ]; then
  key_path="${key_path/#\~/$HOME}"
  if [ ! -f "$key_path" ]; then
    echo "error: no such key file: $key_path" >&2
    exit 1
  fi
  if grep -q "ssh-ed25519" "$key_path"; then
    echo "error: this firmware accepts RSA/DSA keys only; ed25519 is rejected" >&2
    exit 1
  fi

  served_file="/private/tftpboot/fleet.pub"
  echo "sudo is needed to serve the key over TFTP on port 69:"
  sudo -v

  if head -1 "$key_path" | grep -q "BEGIN SSH2"; then
    sudo -n cp "$key_path" "$served_file"
  else
    ssh-keygen -e -f "$key_path" | sudo -n tee "$served_file" >/dev/null
  fi
  sudo -n chmod 644 "$served_file"

  sudo -n launchctl enable system/com.apple.tftpd 2>/dev/null || true
  sudo -n launchctl bootstrap system /System/Library/LaunchDaemons/tftp.plist 2>/dev/null || true
  tftp_started=1

  interface="$(route -n get "$mgmt_ip" 2>/dev/null | awk '/interface:/{print $2}')"
  local_ip="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
  if [ -z "$local_ip" ]; then
    echo "error: could not work out this machine's address toward $mgmt_ip" >&2
    exit 1
  fi

  echo "serving fleet.pub from $local_ip; the switch may take a few minutes"
  console_send "configure" 5 45 1
  console_send "ip ssh download v2 fleet.pub ip-address $local_ip" 50 420 1
  download_output="$CONSOLE_OUT"
  console_send "end" 5 45 1
  case "$download_output" in
    *"Error"*|*"fail"*|*"Fail"*)
      echo "error: key download failed:" >&2
      echo "$download_output" >&2
      exit 1
      ;;
  esac
fi

console_send "show system-info" 15 60 1
info="$CONSOLE_OUT"
console_send "show interface vlan 1" 10 45 1
address="$CONSOLE_OUT"

field() {
  sed -n "s/.*$1[[:space:]]*-[[:space:]]*\(.*\)/\1/p" <<<"$info" | head -1
}

found_name="$(field 'System Name')"
found_hw="$(field 'Hardware Version')"
found_fw="$(field 'Software Version')"
found_mac="$(field 'Mac Address')"
found_serial="$(field 'Serial Number')"
found_ip="$(sed -n 's/.*ip is \([0-9.]*\).*/\1/p' <<<"$address" | head -1)"

if [ "$found_name" != "$switch" ]; then
  echo "error: hostname is '$found_name', expected '$switch'" >&2
  exit 1
fi
if [ "$found_ip" != "$mgmt_ip" ]; then
  echo "error: management address is '$found_ip', expected '$mgmt_ip'" >&2
  exit 1
fi

echo "$found_name ready: $found_hw, firmware $found_fw"
echo "  serial $found_serial, mac $found_mac, management $found_ip"
if [ -n "$key_path" ]; then
  echo "  fleet key imported; connect with ssh -i ${key_path%.pub} $username@$found_ip"
else
  echo "  SSH is enabled, password-only. Pass --import-key to install the fleet key."
fi
