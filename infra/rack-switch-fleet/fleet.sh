#!/usr/bin/env bash
#
# Config as code for a rack's switches. Driven through `mise run rack:fleet`;
# see mise/tasks/rack/fleet.sh for the usage and infra/rack-switch-fleet/AGENTS.md
# for the design.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR

FLEET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FLEET_ROOT/lib/config.sh"
source "$FLEET_ROOT/lib/session.sh"

SITE="ber1"
VERBOSE=0
RUNNING_CONFIG="show running-config"
STARTUP_CONFIG="show startup-config"

site_file() { fleet_site_file "$SITE"; }

config_path() { echo "$FLEET_ROOT/configs/$SITE/$1.cfg"; }
backup_path() { echo "$FLEET_ROOT/backups/$SITE/$1.cfg"; }

devices() {
  if [ -n "${1:-}" ]; then echo "$1"; else fleet_apply_order "$(site_file)"; fi
}

# Read one configuration off a switch into `destination`, in a single session.
#
# Takes a file rather than writing to stdout because the coprocess descriptors
# do not survive into a pipeline's subshell; see lib/session.sh.
read_live_config() {
  local name="$1" command="$2" destination="$3" address user key raw
  address="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mgmt_address' "$(site_file)")"
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"
  raw="$(mktemp)"
  trap switch_close RETURN
  trap 'switch_close; exit 130' INT TERM
  switch_open "$address" "$user" "$key"
  switch_run "$command"
  printf '%s\n' "$SWITCH_OUTPUT" > "$raw"
  fleet_strip_transcript "$command" < "$raw" > "$destination"
  rm -f "$raw"
}

cmd_render() {
  local check=0 name="" stale=0 device rendered target
  while (( $# )); do
    case "$1" in
      --check) check=1; shift;;
      *) name="$1"; shift;;
    esac
  done
  rendered="$(mktemp)"
  for device in $(devices "$name"); do
    target="$(config_path "$device")"
    mkdir -p "$(dirname "$target")"
    fleet_render "$(site_file)" "$device" > "$rendered"
    if (( check )); then
      if ! diff -q "$rendered" "$target" >/dev/null 2>&1; then
        echo "stale: ${target#"$FLEET_ROOT"/}" >&2
        stale=1
      fi
    else
      cp "$rendered" "$target"
      echo "rendered ${target#"$FLEET_ROOT"/}"
    fi
  done
  rm -f "$rendered"
  if (( stale )); then
    echo "the rendered configs no longer match the site definition; run 'mise run rack:fleet render'" >&2
    return 1
  fi
  (( check )) && echo "rendered configs are up to date with the site definition"
  return 0
}

# Non-zero when the switch does not match its render.
device_is_clean() {
  local name="$1" desired live
  desired="$(mktemp)"; live="$(mktemp)"
  fleet_render "$(site_file)" "$name" > "$desired"
  read_live_config "$name" "$RUNNING_CONFIG" "$live"
  local status=0
  fleet_diff "$desired" "$live" "rendered/$name" "live/$name" > "$2" || status=1
  rm -f "$desired" "$live"
  return $status
}

cmd_diff() {
  local name="${1:-}" device drifted=0 report
  report="$(mktemp)"
  for device in $(devices "$name"); do
    if device_is_clean "$device" "$report"; then
      echo "$device: matches the rendered configuration"
    else
      drifted=1
      echo ""
      echo "$device: drifted"
      cat "$report"
    fi
  done
  rm -f "$report"
  return $drifted
}

cmd_drift() {
  local status=0
  cmd_diff || status=$?
  if (( status )); then
    echo "" >&2
    echo "Drift means a switch was changed outside this repository, most likely in the web UI" >&2
    echo "during an incident. Fold the change into the site definition and re-render, or apply" >&2
    echo "to put the switch back." >&2
  fi
  return $status
}

# The apply ordering, enforced rather than written down: a switch is only safe
# to change once every switch with a smaller blast radius already carries the
# change and the rack survived it.
blocking_device() {
  local name="$1" order earlier earlier_order report
  order="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .apply_order' "$(site_file)")"
  report="$(mktemp)"
  for earlier in $(fleet_apply_order "$(site_file)"); do
    earlier_order="$(jq -r --arg n "$earlier" '.devices[] | select(.name == $n) | .apply_order' "$(site_file)")"
    (( earlier_order < order )) || break
    if ! device_is_clean "$earlier" "$report"; then
      rm -f "$report"
      echo "$earlier"
      return 0
    fi
  done
  rm -f "$report"
  return 0
}

cmd_apply() {
  local name="" dry_run=0 assume_yes=0 skip_order=0
  while (( $# )); do
    case "$1" in
      --dry-run) dry_run=1; shift;;
      --yes) assume_yes=1; shift;;
      --skip-order-check) skip_order=1; shift;;
      -*) echo "unknown flag: $1" >&2; return 2;;
      *) name="$1"; shift;;
    esac
  done
  [ -n "$name" ] || { echo "usage: rack:fleet apply <device>" >&2; return 2; }

  local device model spec
  device="$(fleet_device "$(site_file)" "$name")"
  model="$(jq -r '.model' <<<"$device")"
  spec="$(fleet_model "$model")"
  if [ "$(jq -r '.verified' <<<"$spec")" != "true" ]; then
    echo "error: $name is a $(jq -r '.product' <<<"$spec"), whose port naming has never been read" >&2
    echo "       off a live unit. Confirm it, set verified in models.json, then apply." >&2
    return 1
  fi

  if (( ! skip_order )); then
    local blocker
    blocker="$(blocking_device "$name")"
    if [ -n "$blocker" ]; then
      echo "error: $blocker has not been brought to its rendered configuration yet, and it is" >&2
      echo "       applied before $name." >&2
      echo "" >&2
      echo "$blocker: $(jq -r --arg n "$blocker" '.devices[] | select(.name == $n) | .apply_note' "$(site_file)")" >&2
      echo "" >&2
      echo "       Apply to $blocker first, confirm the rack is healthy, then come back." >&2
      return 1
    fi
  fi

  local desired live additions removals commands address user key
  desired="$(mktemp)"; live="$(mktemp)"; additions="$(mktemp)"; removals="$(mktemp)"; commands="$(mktemp)"
  fleet_render "$(site_file)" "$name" > "$desired"
  read_live_config "$name" "$RUNNING_CONFIG" "$live"
  fleet_plan_additions "$desired" "$live" > "$additions"
  fleet_plan_removals "$desired" "$live" > "$removals"

  if [ -s "$removals" ]; then
    echo "$name carries configuration the render does not describe:"
    while IFS=$'\t' read -r context command; do
      echo "  [${context:-global}] $command"
    done < "$removals"
    echo "Turning an arbitrary line into its 'no' form is a guess, so these are left alone."
    echo "Fold them into the site definition, or clear them by hand."
    echo ""
  fi

  if [ ! -s "$additions" ]; then
    echo "$name: already matches the rendered configuration, nothing to apply"
    rm -f "$desired" "$live" "$additions" "$removals" "$commands"
    return 0
  fi

  fleet_plan_commands < "$additions" > "$commands"
  echo "$name ($(jq -r '.mgmt_address' <<<"$device")) would run:"
  sed 's/^/  /' "$commands"

  if (( dry_run )); then
    rm -f "$desired" "$live" "$additions" "$removals" "$commands"
    return 0
  fi

  if (( ! assume_yes )); then
    if [ ! -t 0 ]; then
      echo "error: nothing to confirm from; re-run with --yes or --dry-run" >&2
      return 2
    fi
    echo ""
    echo "$name: $(jq -r '.apply_note' <<<"$device")"
    local answer
    read -r -p "apply? [y/N] " answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || return 130
  fi

  address="$(jq -r '.mgmt_address' <<<"$device")"
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"

  local after
  after="$(mktemp)"
  local raw
  raw="$(mktemp)"
  (
    trap switch_close EXIT
    trap 'switch_close; exit 130' INT TERM
    switch_open "$address" "$user" "$key"
    while IFS= read -r command; do
      (( VERBOSE )) && echo "  $address > $command" >&2
      switch_run "$command"
    done < "$commands"
    switch_run "copy running-config startup-config"
    switch_run "$RUNNING_CONFIG"
    printf '%s\n' "$SWITCH_OUTPUT" > "$raw"
  )
  fleet_strip_transcript "$RUNNING_CONFIG" < "$raw" > "$after"
  rm -f "$raw"

  echo ""
  if fleet_diff "$desired" "$after" "rendered/$name" "live/$name"; then
    echo "$name: applied and verified against the rendered configuration"
    rm -f "$desired" "$live" "$additions" "$removals" "$commands" "$after"
    return 0
  fi
  echo "$name: applied, but the switch still does not match the render"
  rm -f "$desired" "$live" "$additions" "$removals" "$commands" "$after"
  return 1
}

cmd_backup() {
  local name="${1:-}" device target
  for device in $(devices "$name"); do
    target="$(backup_path "$device")"
    mkdir -p "$(dirname "$target")"
    local raw
    raw="$(mktemp)"
    read_live_config "$device" "$STARTUP_CONFIG" "$raw"
    fleet_clean < "$raw" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' > "$target"
    rm -f "$raw"
    echo "backed up $device to ${target#"$FLEET_ROOT"/}"
  done
}

# Serving TFTP needs root, because TFTP is always requested on port 69, and
# tftpd only accepts an upload into a file that already exists and is writable.
# Both halves of that are why this asks for sudo before it asks the switch for
# anything.
TFTP_ROOT_DIR=""
TFTP_SERVED=""

tftp_local_address() {
  local address="$1" interface local_ip
  interface="$(route -n get "$address" 2>/dev/null | awk '/interface:/{print $2}')"
  [ -n "$interface" ] || { echo "error: no route to $address" >&2; return 1; }
  local_ip="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
  [ -n "$local_ip" ] || { echo "error: no address on $interface toward $address" >&2; return 1; }
  echo "$local_ip"
}

tftp_start() {
  local filename="$1"
  TFTP_ROOT_DIR="${TFTP_ROOT:-/private/tftpboot}"
  TFTP_SERVED="$TFTP_ROOT_DIR/$filename"
  echo "sudo is needed to serve TFTP: it is always requested on port 69"
  sudo -v || { echo "error: no sudo, so nothing can listen on port 69" >&2; return 1; }
  sudo mkdir -p "$TFTP_ROOT_DIR" || { echo "error: could not create $TFTP_ROOT_DIR" >&2; return 1; }
  if ! sudo touch "$TFTP_SERVED" || ! sudo chmod 666 "$TFTP_SERVED"; then
    echo "error: could not create a writable $TFTP_SERVED" >&2
    return 1
  fi
  sudo launchctl enable system/com.apple.tftpd >/dev/null 2>&1 || true
  sudo launchctl bootout system/com.apple.tftpd >/dev/null 2>&1 || true
  local failure
  failure="$(sudo launchctl bootstrap system /System/Library/LaunchDaemons/tftp.plist 2>&1)" || {
    echo "error: could not start tftpd: ${failure:-no message}" >&2
    sudo rm -f "$TFTP_SERVED"
    return 1
  }
}

tftp_stop() {
  sudo launchctl bootout system/com.apple.tftpd >/dev/null 2>&1 || true
  [ -n "$TFTP_SERVED" ] && sudo rm -f "$TFTP_SERVED"
  TFTP_SERVED=""
}

# Wait for a switch to go away and come back. A reboot that never completes is
# the failure this has to report rather than hang on.
wait_for_reboot() {
  local address="$1" waited=0
  echo "waiting for $address to go down"
  while (( waited < 60 )) && ping -c 1 -W 2000 "$address" >/dev/null 2>&1; do
    sleep 2; waited=$(( waited + 2 ))
  done
  if (( waited >= 60 )); then
    echo "error: $address never went down; the reboot did not take" >&2
    return 1
  fi
  echo "waiting for $address to come back"
  waited=0
  while (( waited < 300 )); do
    if nc -z -w 3 "$address" 22 >/dev/null 2>&1; then
      echo "$address is back after ${waited}s"
      return 0
    fi
    sleep 5; waited=$(( waited + 5 ))
  done
  echo "error: $address did not answer SSH within 300s of rebooting" >&2
  return 1
}

# What is plugged into each port, read off the site definition rather than a
# switch. Wiring a rack is easier to check against a list than against a diagram.
cmd_ports() {
  local name="${1:-}" device port purpose peer detail
  for device in $(devices "$name"); do
    echo "$device"
    while IFS=$'\t' read -r port purpose peer detail; do
      [ -n "$port" ] || continue
      printf '  %-4s %-8s %-14s %s\n' "$port" "$purpose" "$peer" "$detail"
    done < <(fleet_port_map "$(site_file)" "$device")
    echo ""
  done
  local unassigned
  unassigned="$(jq -r '.nodes[]? as $n | $n.links[] | select(.port == null) |
    "  \($n.name)\(if $n.status == "planned" then " (planned)" else "" end) -> \(.switch)"' "$(site_file)")"
  if [ -n "$unassigned" ]; then
    echo "links with no port assigned yet:"
    printf '%s\n' "$unassigned"
  fi
}

# The switch's terminal lines, and how to free one.
#
# This firmware does not reap a session a client abandoned, and it only frees
# one on `logout`, so a crashed run leaks a line. Enough of those and the SSH
# daemon stops accepting connections altogether while the switch keeps
# forwarding. `clear line <tid>` is the way out that does not involve power.
cmd_sessions() {
  local name="${1:-}" tid="${2:-}"
  [ -n "$name" ] || { echo "usage: rack:fleet sessions <device> [tid-to-clear]" >&2; return 2; }
  local address user key raw
  address="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mgmt_address' "$(site_file)")"
  [ -n "$address" ] || { echo "error: $name is not in $SITE" >&2; return 1; }
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"
  raw="$(mktemp)"
  (
    trap switch_close EXIT
    trap 'switch_close; exit 130' INT TERM
    switch_open "$address" "$user" "$key" || exit 1
    if [ -n "$tid" ]; then
      switch_run "clear line $tid" || exit 1
      echo "cleared line $tid on $name"
    fi
    switch_run "show users" || exit 1
    printf '%s\n' "$SWITCH_OUTPUT" > "$raw"
  ) || { rm -f "$raw"; return 1; }
  tr -d '\000\r' < "$raw" | sed -n '/tid/,$p' | sed '/^[[:space:]]*$/d;$d'
  rm -f "$raw"
  echo ""
  echo "One of those is this command. Free a leaked line with:"
  echo "  mise run rack:fleet sessions $name <tid>"
}

# Replace a switch's whole configuration with the rendered one.
#
# The shape the design prefers, now that the export is known to be text:
# idempotent by construction, and the change path and the disaster-recovery path
# are the same code. It costs a reboot, which the A/B pair is what makes
# affordable, and it is why ber1-tor-b goes first and ber1-mgmt alone and last.
#
# The switch's current configuration is exported first and merged, because the
# render deliberately omits the admin login: pushing it bare would delete the
# account used to log in. See lib/merge.awk.
cmd_replace() {
  local name="" dry_run=0 assume_yes=0 skip_order=0 do_reboot=0
  while (( $# )); do
    case "$1" in
      --dry-run) dry_run=1; shift;;
      --yes) assume_yes=1; shift;;
      --reboot) do_reboot=1; shift;;
      --skip-order-check) skip_order=1; shift;;
      -*) echo "unknown flag: $1" >&2; return 2;;
      *) name="$1"; shift;;
    esac
  done
  [ -n "$name" ] || { echo "usage: rack:fleet replace <device> [--dry-run] [--reboot]" >&2; return 2; }

  local device model spec address user key
  device="$(fleet_device "$(site_file)" "$name")"
  model="$(jq -r '.model' <<<"$device")"
  spec="$(fleet_model "$model")"
  if [ "$(jq -r '.verified' <<<"$spec")" != "true" ]; then
    echo "error: $name is a $(jq -r '.product' <<<"$spec"), whose port naming has never been" >&2
    echo "       read off a live unit. Confirm it, set verified in models.json, then replace." >&2
    return 1
  fi
  if (( ! skip_order )); then
    local blocker
    blocker="$(blocking_device "$name")"
    if [ -n "$blocker" ]; then
      echo "error: $blocker is applied before $name and is not at its rendered configuration yet." >&2
      echo "" >&2
      echo "$blocker: $(jq -r --arg n "$blocker" '.devices[] | select(.name == $n) | .apply_note' "$(site_file)")" >&2
      return 1
    fi
  fi

  address="$(jq -r '.mgmt_address' <<<"$device")"
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"

  local local_ip export_name push_name current rendered merged
  local_ip="$(tftp_local_address "$address")" || return 1
  export_name="$name-current.cfg"
  push_name="$name-desired.cfg"
  current="$(mktemp)"; rendered="$(mktemp)"; merged="$(mktemp)"
  fleet_render "$(site_file)" "$name" > "$rendered"

  tftp_start "$export_name" || return 1
  echo "asking $name for its current startup config"
  local status=0
  (
    trap switch_close EXIT
    trap 'switch_close; exit 130' INT TERM
    switch_open "$address" "$user" "$key" || exit 1
    switch_run "copy startup-config tftp ip-address $local_ip filename $export_name" 180 || exit 1
  ) || status=$?
  if (( status )) || [ ! -s "$TFTP_SERVED" ]; then
    echo "error: could not read $name's current configuration, so there is nothing safe to merge" >&2
    tftp_stop
    return 1
  fi
  cp "$TFTP_SERVED" "$current"
  tftp_stop

  fleet_merge_unmanaged "$current" "$rendered" > "$merged"
  if ! grep -q '^user name ' "$merged"; then
    echo "error: the merged configuration has no login in it. Refusing to push a file that" >&2
    echo "       would lock everyone out of $name." >&2
    return 1
  fi

  echo ""
  echo "$name would change:"
  if fleet_diff "$current" "$merged" "live/$name" "rendered/$name"; then
    echo "  nothing; the switch already matches the rendered configuration"
    if (( ! assume_yes )) && (( ! dry_run )); then
      echo "  (replacing anyway would still cost a reboot)"
    fi
  fi

  if (( dry_run )); then
    echo ""
    echo "the file that would be pushed is $merged"
    return 0
  fi

  if (( ! assume_yes )); then
    if [ ! -t 0 ]; then
      echo "error: nothing to confirm from; re-run with --yes or --dry-run" >&2
      return 2
    fi
    echo ""
    echo "$name: $(jq -r '.apply_note' <<<"$device")"
    echo "This overwrites the startup config and needs a reboot to take effect."
    local answer
    read -r -p "replace? [y/N] " answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || return 130
  fi

  tftp_start "$push_name" || return 1
  fleet_device_file < "$merged" | sudo tee "$TFTP_SERVED" >/dev/null
  sudo chmod 644 "$TFTP_SERVED"
  echo "pushing to $name"
  status=0
  (
    trap switch_close EXIT
    trap 'switch_close; exit 130' INT TERM
    switch_open "$address" "$user" "$key" || exit 1
    switch_run "copy tftp startup-config ip-address $local_ip filename $push_name" 180 || exit 1
    if (( do_reboot )); then
      echo "rebooting $name"
      switch_run_confirm "reboot" "Y" 30 || true
    fi
  ) || status=$?
  tftp_stop
  if (( status )); then
    echo "error: $name did not accept the configuration" >&2
    return "$status"
  fi

  if (( ! do_reboot )); then
    echo ""
    echo "$name: startup config replaced. It takes effect on the next reboot, which this did"
    echo "not do. Reboot it, then confirm with:"
    echo "  mise run rack:fleet diff $name"
    return 0
  fi

  wait_for_reboot "$address" || return 1
  local after
  after="$(mktemp)"
  read_live_config "$name" "$RUNNING_CONFIG" "$after"
  echo ""
  if fleet_diff "$rendered" "$after" "rendered/$name" "live/$name"; then
    echo "$name: replaced, rebooted and verified against the rendered configuration"
    rm -f "$current" "$rendered" "$merged" "$after"
    return 0
  fi
  echo "$name: came back, but does not match the render"
  rm -f "$current" "$rendered" "$merged" "$after"
  return 1
}

# Answer the open question: is the exported config text, or is it opaque?
#
# If it is text, a change becomes `copy tftp startup-config` of a file rendered
# from this repository, the restore path and the change path become the same
# code, and DHCP Auto Install has something to serve. If it is opaque, config as
# code here can only ever drive the CLI.
#
# Every step announces itself and every failure says which one it was: this runs
# once in a blue moon, under sudo, against one switch, and a silent exit here
# tells the operator nothing.
cmd_probe_tftp() {
  local name="${1:-}"
  [ -n "$name" ] || { echo "usage: rack:fleet probe-tftp <device>" >&2; return 2; }

  local address interface local_ip filename tftp_root served
  address="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mgmt_address' "$(site_file)")"
  [ -n "$address" ] || { echo "error: $name is not in $SITE" >&2; return 1; }
  interface="$(route -n get "$address" 2>/dev/null | awk '/interface:/{print $2}')"
  [ -n "$interface" ] || { echo "error: no route to $address" >&2; return 1; }
  local_ip="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
  [ -n "$local_ip" ] || { echo "error: no address on $interface toward $address" >&2; return 1; }

  filename="$name-probe.cfg"
  tftp_root="${TFTP_ROOT:-/private/tftpboot}"
  served="$tftp_root/$filename"

  echo "sudo is needed to serve TFTP: it is always requested on port 69"
  if ! sudo -v; then
    echo "error: no sudo, so nothing can listen on port 69" >&2
    return 1
  fi

  echo "preparing $served"
  if ! sudo mkdir -p "$tftp_root"; then
    echo "error: could not create $tftp_root" >&2
    return 1
  fi
  # tftpd only accepts an upload into a file that already exists and is
  # writable, so the placeholder is the whole reason this needs root twice.
  if ! sudo touch "$served" || ! sudo chmod 666 "$served"; then
    echo "error: could not create a writable $served" >&2
    return 1
  fi

  echo "starting tftpd"
  sudo launchctl enable system/com.apple.tftpd >/dev/null 2>&1 || true
  sudo launchctl bootout system/com.apple.tftpd >/dev/null 2>&1 || true
  local bootstrap_error
  bootstrap_error="$(sudo launchctl bootstrap system /System/Library/LaunchDaemons/tftp.plist 2>&1)" || {
    echo "error: could not start tftpd: ${bootstrap_error:-no message}" >&2
    sudo rm -f "$served"
    return 1
  }

  local user key status=0
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"

  echo "asking $name to send its startup config to $local_ip"
  (
    trap switch_close EXIT
    trap 'switch_close; exit 130' INT TERM
    switch_open "$address" "$user" "$key" || exit 1
    switch_run "copy startup-config tftp ip-address $local_ip filename $filename" 180 || exit 1
    printf '%s\n' "$SWITCH_OUTPUT"
  ) || status=$?

  sudo launchctl bootout system/com.apple.tftpd >/dev/null 2>&1 || true

  if (( status )); then
    echo "error: the switch did not complete the export (exit $status)" >&2
    sudo rm -f "$served"
    return "$status"
  fi

  local size printable ratio destination
  size="$(wc -c < "$served" | tr -d ' ')"
  if [ "$size" = "0" ]; then
    echo "error: the switch reported no failure but wrote nothing." >&2
    echo "       TFTP replies from a fresh port, so check the macOS firewall is not" >&2
    echo "       blocking incoming UDP for /usr/libexec/tftpd." >&2
    sudo rm -f "$served"
    return 1
  fi

  printable="$(LC_ALL=C tr -dc '\11\12\13\14\15\40-\176' < "$served" | wc -c | tr -d ' ')"
  ratio=$(( printable * 100 / size ))
  # Deliberately outside the repository: if the export is text it is a whole
  # startup config, admin hash and all. `rack:fleet backup` is the way to get a
  # copy into git, because that one redacts.
  destination="$(mktemp -t "$name-tftp-probe")"
  cp "$served" "$destination"
  sudo rm -f "$served"

  echo ""
  echo "$size bytes, ${ratio}% printable, left at $destination"
  echo "(outside the repo on purpose: a text export carries the admin hash)"
  if (( ratio > 95 )); then
    echo "TEXT. The config round-trips as readable text, so a change can be a whole-config"
    echo "replace: render, 'copy tftp startup-config', reboot, re-read, diff. DHCP Auto"
    echo "Install has something to serve too."
  else
    echo "OPAQUE. The exported file is not text, so the rendered state cannot be pushed whole."
    echo "Config as code here stays CLI-driven, with 'show running-config' as the diff source."
  fi
}

main() {
  while (( $# )); do
    case "$1" in
      --site) SITE="${2:-}"; shift 2;;
      --verbose) VERBOSE=1; shift;;
      *) break;;
    esac
  done
  local command="${1:-}"
  [ -n "$command" ] || { echo "usage: mise run rack:fleet <render|diff|apply|replace|backup|drift|ports|sessions|probe-tftp>" >&2; return 2; }
  shift
  [ -f "$(site_file)" ] || { echo "error: no site definition at $(site_file)" >&2; return 2; }
  case "$command" in
    render)     cmd_render "$@";;
    diff)       cmd_diff "$@";;
    apply)      cmd_apply "$@";;
    backup)     cmd_backup "$@";;
    sessions)   cmd_sessions "$@";;
    ports)      cmd_ports "$@";;
    replace)    cmd_replace "$@";;
    drift)      cmd_drift "$@";;
    probe-tftp) cmd_probe_tftp "$@";;
    *) echo "unknown command: $command" >&2; return 2;;
  esac
}

main "$@"
