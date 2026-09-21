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

# Answer the open question: is the exported config text, or is it opaque?
#
# If it is text, a change becomes `copy tftp startup-config` of a file rendered
# from this repository, and the restore path and the change path become the same
# code. If it is opaque, config as code here can only ever drive the CLI.
cmd_probe_tftp() {
  local name="${1:-}"
  [ -n "$name" ] || { echo "usage: rack:fleet probe-tftp <device>" >&2; return 2; }
  local address interface local_ip filename served
  address="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mgmt_address' "$(site_file)")"
  [ -n "$address" ] || { echo "error: $name is not in $SITE" >&2; return 1; }
  interface="$(route -n get "$address" 2>/dev/null | awk '/interface:/{print $2}')"
  [ -n "$interface" ] || { echo "error: no route to $address" >&2; return 1; }
  local_ip="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
  [ -n "$local_ip" ] || { echo "error: no address on $interface toward $address" >&2; return 1; }

  filename="$name-probe.cfg"
  served="/private/tftpboot/$filename"

  echo "sudo is needed to serve TFTP: it is always requested on port 69"
  sudo -v
  sudo touch "$served"
  sudo chmod 666 "$served"
  sudo launchctl enable system/com.apple.tftpd 2>/dev/null || true
  sudo launchctl bootstrap system /System/Library/LaunchDaemons/tftp.plist 2>/dev/null || true

  local user key status=0
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"
  (
    trap switch_close EXIT
    switch_open "$address" "$user" "$key"
    switch_run "copy startup-config tftp ip-address $local_ip filename $filename" 180
  ) || status=$?
  sudo launchctl bootout system/com.apple.tftpd 2>/dev/null || true

  if (( status )); then
    sudo rm -f "$served"
    return $status
  fi

  local size printable ratio destination
  size="$(wc -c < "$served" | tr -d ' ')"
  if [ "$size" = "0" ]; then
    echo "error: the switch wrote nothing; the transfer did not complete" >&2
    sudo rm -f "$served"
    return 1
  fi
  printable="$(LC_ALL=C tr -dc '\11\12\13\14\15\40-\176' < "$served" | wc -c | tr -d ' ')"
  ratio=$(( printable * 100 / size ))
  destination="$FLEET_ROOT/backups/$SITE/$name-tftp-probe.bin"
  mkdir -p "$(dirname "$destination")"
  cp "$served" "$destination"
  sudo rm -f "$served"

  echo ""
  echo "$size bytes, ${ratio}% printable, saved to ${destination#"$FLEET_ROOT"/}"
  if (( ratio > 95 )); then
    echo "TEXT. The config round-trips as readable text, so a change can be a whole-config"
    echo "replace: render, 'copy tftp startup-config', reboot, re-read, diff."
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
  [ -n "$command" ] || { echo "usage: mise run rack:fleet <render|diff|apply|backup|drift|probe-tftp>" >&2; return 2; }
  shift
  [ -f "$(site_file)" ] || { echo "error: no site definition at $(site_file)" >&2; return 2; }
  case "$command" in
    render)     cmd_render "$@";;
    diff)       cmd_diff "$@";;
    apply)      cmd_apply "$@";;
    backup)     cmd_backup "$@";;
    drift)      cmd_drift "$@";;
    probe-tftp) cmd_probe_tftp "$@";;
    *) echo "unknown command: $command" >&2; return 2;;
  esac
}

main "$@"
