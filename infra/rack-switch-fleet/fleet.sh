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
# Long enough to apply and verify, short enough that a change which cut off the
# management path is undone before anyone has to go and find a console cable.
ROLLBACK_MINUTES=5

site_file() { fleet_site_file "$SITE"; }

config_path() { echo "$FLEET_ROOT/configs/$SITE/$1.cfg"; }
k8s_path()    { echo "$FLEET_ROOT/k8s/$SITE/$1.yaml"; }
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
  local object
  object="$(mktemp)"
  for device in $(devices "$name"); do
    target="$(config_path "$device")"
    mkdir -p "$(dirname "$target")"
    fleet_render "$(site_file)" "$device" > "$rendered"
    # The RackSwitch object is derived from the same site definition, so the
    # cluster's view of a switch cannot drift from the configuration rendered
    # for it. Its configRevision is the digest of exactly this file.
    local object_target
    object_target="$(k8s_path "$device")"
    mkdir -p "$(dirname "$object_target")"
    fleet_render_k8s "$(site_file)" "$device" > "$object"
    if (( check )); then
      if ! diff -q "$rendered" "$target" >/dev/null 2>&1; then
        echo "stale: ${target#"$FLEET_ROOT"/}" >&2
        stale=1
      fi
      if ! diff -q "$object" "$object_target" >/dev/null 2>&1; then
        echo "stale: ${object_target#"$FLEET_ROOT"/}" >&2
        stale=1
      fi
    else
      cp "$rendered" "$target"
      cp "$object" "$object_target"
      echo "rendered ${target#"$FLEET_ROOT"/} and ${object_target#"$FLEET_ROOT"/}"
    fi
  done
  rm -f "$rendered" "$object"
  if (( stale )); then
    echo "the rendered configs no longer match the site definition; run 'mise run rack:fleet render'" >&2
    return 1
  fi
  (( check )) && echo "rendered configs are up to date with the site definition"
  return 0
}

device_adopted() {
  [ "$(jq -r --arg n "$1" '.devices[] | select(.name == $n) | .adopted // false' "$(site_file)")" = true ]
}

# An adopted switch is compared against its render with what the controller
# owns and adds left out, which needs that measured for its model. One that has
# not been is refused before its SSH connection is spent.
require_baseline() {
  local name="$1" model
  device_adopted "$name" || return 0
  model="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .model' "$(site_file)")"
  [ -f "$(fleet_controller_baseline "$model")" ] && return 0
  echo "error: $name is adopted, and what the controller does to a $model has not been measured;" >&2
  echo "       record it in controller-baselines/$model.tsv first" >&2
  return 1
}

fleet_compare() {
  local name="$1" desired="$2" actual="$3" label_desired="$4" label_actual="$5" model
  if ! device_adopted "$name"; then
    fleet_diff "$desired" "$actual" "$label_desired" "$label_actual"
    return
  fi
  model="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .model' "$(site_file)")"
  fleet_diff_adopted "$desired" "$actual" "$label_desired" "$label_actual" "$(fleet_controller_baseline "$model")"
}

# The controller owns an adopted switch's configuration, and TP-Link documents
# SSH in controller mode as show commands only, so no SSH write path runs
# against one; its changes go through `rack:omada apply`.
refuse_adopted() {
  local arg
  for arg in "$@"; do
    [ "${arg#-}" = "$arg" ] || continue
    if device_adopted "$arg"; then
      echo "error: $arg is adopted by the site's controller, which owns its configuration;" >&2
      echo "       change it with: mise run rack:omada apply $arg" >&2
      return 1
    fi
  done
}

# Non-zero when the switch does not match its render.
device_is_clean() {
  local name="$1" desired live
  require_baseline "$name" || exit 2
  desired="$(mktemp)"; live="$(mktemp)"
  fleet_render "$(site_file)" "$name" > "$desired"
  read_live_config "$name" "$RUNNING_CONFIG" "$live"
  local status=0
  fleet_compare "$name" "$desired" "$live" "rendered/$name" "live/$name" > "$2" || status=1
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
  fleet_lock "apply $name" || return 1

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
    # Split by hand: tab is whitespace to `read`, which drops an empty leading
    # field and would print a global line's command as its context.
    local line context
    while IFS= read -r line; do
      context="${line%%$'\t'*}"
      echo "  [${context:-global}] ${line#*$'\t'}"
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

  # A confirmed commit. Before anything changes the switch is told to reboot in
  # ROLLBACK_MINUTES without saving, so a change that cuts off this session, or
  # one that does not verify, is undone by the switch itself: it comes back on
  # its saved configuration. The timer is cancelled only once the running
  # configuration matches the render, and only then is it saved.
  local startup after raw status=0
  startup="$(mktemp)"; after="$(mktemp)"; raw="$(mktemp)"
  (
    trap switch_close EXIT
    trap 'switch_close; exit 130' INT TERM
    switch_open "$address" "$user" "$key" || exit 10
    # Rolling back returns the switch to its saved configuration, so anything
    # unsaved on it would be thrown away along with the change.
    switch_run "$STARTUP_CONFIG" || exit 10
    printf '%s\n' "$SWITCH_OUTPUT" > "$raw"
    fleet_strip_transcript "$STARTUP_CONFIG" < "$raw" > "$startup"
    fleet_diff "$live" "$startup" "running/$name" "startup/$name" >/dev/null || exit 11
    switch_run "configure" || exit 10
    switch_run_confirm "reboot-schedule in $ROLLBACK_MINUTES" "Y" 30 || exit 16
    switch_run "end" || exit 12
    while IFS= read -r command; do
      (( VERBOSE )) && echo "  $address > $command" >&2
      switch_run "$command" || exit 12
    done < "$commands"
    switch_run "$RUNNING_CONFIG" || exit 12
    printf '%s\n' "$SWITCH_OUTPUT" > "$raw"
    fleet_strip_transcript "$RUNNING_CONFIG" < "$raw" > "$after"
    echo ""
    fleet_diff "$desired" "$after" "rendered/$name" "live/$name" || exit 13
    switch_run "configure" || exit 14
    switch_run_confirm "reboot-schedule cancel" "Y" 30 || exit 14
    switch_run "end" || exit 14
    switch_run "copy running-config startup-config" || exit 15
  ) || status=$?
  rm -f "$desired" "$live" "$additions" "$removals" "$commands" "$startup" "$after" "$raw"

  local rollback="$name reboots on its saved configuration within $ROLLBACK_MINUTES minutes of the start"
  case "$status" in
    0)  echo "$name: applied, verified against the rendered configuration, and saved";;
    10) echo "error: $name: nothing was changed" >&2;;
    11) echo "error: $name has unsaved changes. Rolling back returns it to its saved configuration," >&2
        echo "       which would discard them. Save or discard them first; nothing was changed." >&2;;
    16) echo "error: $name: the rollback timer could not be confirmed, so nothing was changed." >&2
        echo "       If it was armed after all, $rollback, unchanged." >&2;;
    12) echo "error: the change did not complete. $rollback." >&2;;
    13) echo "error: $name does not match the render after applying, so nothing was saved." >&2
        echo "       $rollback." >&2;;
    14) echo "error: $name matched the render but the rollback timer could not be cancelled." >&2
        echo "       $rollback, dropping the change; apply again once it is back." >&2;;
    15) echo "error: $name matches the render and the timer is cancelled, but saving failed." >&2
        echo "       The running configuration is right and unsaved; apply again to save it." >&2;;
    *)  echo "error: $name: interrupted; if the timer was armed, $rollback." >&2;;
  esac
  return $status
}

# Save the running configuration, but only once it matches the render, and in
# the same connection that checked it. Its caller is a switch rack:ztp just
# provisioned, whose startup configuration is the served file verbatim.
cmd_save() {
  local name="${1:-}"
  [ -n "$name" ] || { echo "usage: rack:fleet save <device>" >&2; return 2; }
  fleet_lock "save $name" || return 1
  local address user key desired raw body status=0
  address="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mgmt_address' "$(site_file)")"
  [ -n "$address" ] || { echo "error: $name is not in $SITE" >&2; return 1; }
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"
  desired="$(mktemp)"; raw="$(mktemp)"; body="$(mktemp)"
  fleet_render "$(site_file)" "$name" > "$desired"
  (
    trap switch_close EXIT
    trap 'switch_close; exit 130' INT TERM
    switch_open "$address" "$user" "$key" || exit 10
    switch_run "$RUNNING_CONFIG" || exit 10
    printf '%s\n' "$SWITCH_OUTPUT" > "$raw"
    fleet_strip_transcript "$RUNNING_CONFIG" < "$raw" > "$body"
    fleet_diff "$desired" "$body" "rendered/$name" "live/$name" || exit 11
    switch_run "copy running-config startup-config" || exit 12
  ) || status=$?
  rm -f "$desired" "$raw" "$body"
  case "$status" in
    0)  echo "$name: running configuration matches the render and is saved";;
    11) echo "error: $name does not match the render, so nothing was saved" >&2;;
    12) echo "error: $name matches the render but refused the save" >&2;;
    *)  echo "error: $name: nothing was saved" >&2;;
  esac
  return "$status"
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

# One change at a time per rack.
#
# The apply ordering refuses a switch whose predecessors are not at the render,
# which is a check on state and not a lock. Two runs started together both see
# clean predecessors and both proceed, so "never both ToRs at once" was true of
# a careful operator and not of the tool. The lock is held across the change and
# its verification, so the second run waits for the first to be proven rather
# than merely finished.
#
# mkdir because macOS has no flock: it is the one atomic primitive available
# here, and it leaves the holder's pid behind so a killed run can be recognised.
#
# A fixed path rather than TMPDIR, because TMPDIR differs per shell and per user
# and two runs that do not share one would not see each other's lock at all.
# This still only coordinates runs on one machine: two laptops, or a laptop and
# a CI job, are not serialised by it. A Lease is the answer to that, and it
# needs something in the cluster to hold one.
FLEET_LOCK=""

fleet_lock() {
  local reason="$1" dir owner pid
  dir="${FLEET_LOCK_DIR:-/tmp}/rack-fleet-$SITE.lock"

  # `mkdir` and nothing else. Reclaiming a stale lock automatically means
  # removing a directory this process did not create, and two runs that both
  # read the same dead owner will both remove it: the second one deletes the
  # lock the first just acquired, and then creates its own. Checking the second
  # `mkdir` does not help, because by then the damage is the `rm`. There is no
  # ordering of remove-then-create that is safe without a primitive this does
  # not have, so a stale lock is a thing a human clears.
  if mkdir "$dir" 2>/dev/null; then
    printf '%s %s\n' "$$" "$reason" > "$dir/owner"
    FLEET_LOCK="$dir"
    trap fleet_unlock EXIT
    return 0
  fi

  owner="$(cat "$dir/owner" 2>/dev/null || echo unknown)"
  pid="${owner%% *}"
  echo "error: another change is in flight on $SITE: $owner" >&2
  if [ "$owner" != unknown ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "       Process $pid is gone, so this is probably a run that was killed. Nothing" >&2
    echo "       clears it automatically, because a second run doing that races the first." >&2
    echo "       Check no change is actually in progress, then: rm -rf $dir" >&2
  else
    echo "       Only one switch in a rack is changed at a time. Wait for it to finish." >&2
  fi
  return 1
}


fleet_unlock() {
  [ -n "$FLEET_LOCK" ] || return 0
  rm -rf "$FLEET_LOCK"
  FLEET_LOCK=""
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

# Everything worth knowing before a change, in one connection.
#
# This firmware allows seven SSH connections per boot and does not recycle the
# slots, so connections are a consumable. Run separately, `sessions`, `diff` and
# `backup` cost three of the seven and `replace` costs two more, which is most
# of the budget before anything has been changed. They ask the switch three
# questions, so they are one connection, not three.
cmd_preflight() {
  local name="${1:-}"
  [ -n "$name" ] || { echo "usage: rack:fleet preflight <device>" >&2; return 2; }
  require_baseline "$name" || return 2
  local address user key users running startup desired status=0
  address="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mgmt_address' "$(site_file)")"
  [ -n "$address" ] || { echo "error: $name is not in $SITE" >&2; return 1; }
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"
  users="$(mktemp)"; running="$(mktemp)"; startup="$(mktemp)"; desired="$(mktemp)"

  (
    trap switch_close EXIT
    trap 'switch_close; exit 130' INT TERM
    switch_open "$address" "$user" "$key" || exit 1
    switch_run "show users" || exit 1
    printf '%s\n' "$SWITCH_OUTPUT" > "$users"
    switch_run "$RUNNING_CONFIG" || exit 1
    printf '%s\n' "$SWITCH_OUTPUT" > "$running"
    switch_run "$STARTUP_CONFIG" || exit 1
    printf '%s\n' "$SWITCH_OUTPUT" > "$startup"
  ) || status=$?
  if (( status )); then
    rm -f "$users" "$running" "$startup" "$desired"
    return "$status"
  fi

  echo "terminal lines on $name (this connection is one of them):"
  tr -d '\000\r' < "$users" | sed -n '/tid/,$p' | sed '/^[[:space:]]*$/d;$d' | sed 's/^/  /'
  local used
  # A listing with no SSH task in it must not end the run under pipefail.
  used="$(fleet_current_connection < "$users" || true)"
  if [ -n "$used" ]; then
    echo "  this is connection $(( 10#$used + 1 )) since boot, of about eight before the daemon stops accepting"
  fi

  local body
  body="$(mktemp)"
  fleet_strip_transcript "$RUNNING_CONFIG" < "$running" > "$body"
  fleet_render "$(site_file)" "$name" > "$desired"
  echo ""
  if fleet_compare "$name" "$desired" "$body" "rendered/$name" "live/$name"; then
    echo "$name: matches the rendered configuration"
  else
    status=1
    echo "$name: drifted, see above"
  fi

  local target
  target="$(backup_path "$name")"
  mkdir -p "$(dirname "$target")"
  fleet_strip_transcript "$STARTUP_CONFIG" < "$startup" > "$body"
  # Auto Install saves the file it fetched verbatim, so a switch provisioned by
  # rack:ztp starts with its login in plaintext and a key download that runs at
  # every boot, until its own running configuration is saved over them once.
  if grep -qE '^user name .* secret 0 |^ip ssh download ' "$body"; then
    status=1
    echo ""
    echo "$name: its startup configuration is still the file it was provisioned from, with"
    echo "the login in plaintext and a key download that runs at every boot. Seal it with:"
    echo "  mise run rack:fleet save $name"
  fi
  fleet_clean < "$body" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' > "$target"
  echo ""
  echo "backed up $name to ${target#"$FLEET_ROOT"/}"

  rm -f "$users" "$running" "$startup" "$desired" "$body"
  return "$status"
}

# Find a switch that is not where the site definition says it is.
#
# The address moves: a factory reset, or Auto Install putting VLAN 1 on DHCP
# while it looks for a provisioning server. The MAC does not, so that is what
# identifies the switch when the address has stopped doing so.
cmd_locate() {
  local name="${1:-}"
  [ -n "$name" ] || { echo "usage: rack:fleet locate <device>" >&2; return 2; }
  local mac expected found
  mac="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mac // empty' "$(site_file)")"
  expected="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mgmt_address' "$(site_file)")"
  if [ -z "$mac" ]; then
    echo "error: $name has no mac in the site definition, so it can only be found by address" >&2
    return 1
  fi

  if ping -c 1 -W 2000 "$expected" >/dev/null 2>&1; then
    echo "$name answers at $expected, where it should be"
  fi
  echo "sweeping the management prefix so the ARP table is populated"
  local prefix base i
  prefix="$(jq -r '.management.prefix' "$(site_file)")"
  base="${prefix%.*}"
  for i in $(seq 1 254); do ( ping -c 1 -W 300 "$base.$i" >/dev/null 2>&1 & ) ; done
  sleep 10

  # macOS arp prints a MAC without leading zeroes, so compare on that form
  local short="${mac//:0/:}"
  short="${short#0}"
  found="$(arp -an | awk -v mac="$short" '
      tolower($4) == mac { gsub(/[()]/, "", $2); print $2 }' | sort -u)"
  if [ -z "$found" ]; then
    echo "error: nothing on $prefix answers for $mac. It may be off, on another VLAN," >&2
    echo "       or reachable only over the console." >&2
    return 1
  fi
  echo ""
  echo "$name ($mac) is at:"
  printf '%s\n' "$found" | sed 's/^/  /' 
  local address
  while IFS= read -r address; do
    [ "$address" = "$expected" ] && continue
    echo ""
    echo "That is not $expected. Put it back with:"
    echo "  mise run rack:fleet recover $name --from $address"
    break
  done <<<"$found"
}

# Put a switch that moved back on its site address, and save it.
#
# Two sessions on purpose. Changing the address drops the session that changed
# it, so the save cannot happen in the same one, and a save that never ran is
# how a switch comes back on DHCP after the next reboot.
cmd_recover() {
  local name="" from="" assume_yes=0
  while (( $# )); do
    case "$1" in
      --from) from="${2:-}"; shift 2;;
      --yes) assume_yes=1; shift;;
      -*) echo "unknown flag: $1" >&2; return 2;;
      *) name="$1"; shift;;
    esac
  done
  if [ -z "$name" ] || [ -z "$from" ]; then
    echo "usage: rack:fleet recover <device> --from <current-address>" >&2
    return 2
  fi
  fleet_lock "recover $name" || return 1

  local device address netmask vlan user key
  device="$(fleet_device "$(site_file)" "$name")" || return 1
  address="$(jq -r '.mgmt_address' <<<"$device")"
  netmask="$(jq -r '.management.netmask' "$(site_file)")"
  vlan="$(jq -r '.management.vlan' "$(site_file)")"
  user="$(jq -r '.credentials.username' "$(site_file)")"
  key="$(jq -r '.credentials.ssh_key' "$(site_file)")"

  echo "$name is at $from and belongs at $address"
  if (( ! assume_yes )); then
    [ -t 0 ] || { echo "error: nothing to confirm from; re-run with --yes" >&2; return 2; }
    local answer; read -r -p "move it back? [y/N] " answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || return 130
  fi

  # Only the address command is allowed to fail, because it is the one that
  # drops the session. A refused login, `configure` or `interface` means nothing
  # was changed, and carrying on from there would save whatever is already on
  # the switch, which is the state recovery exists to correct.
  echo "session 1: setting the address, which will drop this session"
  local setup=0
  (
    trap switch_close EXIT
    switch_open "$from" "$user" "$key" || exit 10
    switch_run "configure" 30 || exit 11
    switch_run "interface vlan $vlan" 30 || exit 12
    # Its failure is the session dropping as the address moves, which is the
    # expected outcome; whether the address actually took is checked in session
    # two, so the driver's timeout message would only read as a false alarm.
    switch_run "ip address $address $netmask" 20 2>/dev/null || echo "session dropped as the address moved, as expected"
  ) || setup=$?
  case "$setup" in
    0)  ;;
    10) echo "error: could not open a session to $name at $from; nothing was changed" >&2; return 1;;
    11) echo "error: $from refused 'configure'; nothing was changed" >&2; return 1;;
    12) echo "error: $from refused 'interface vlan $vlan'; nothing was changed" >&2; return 1;;
    *)  echo "error: $from failed ($setup) before the address was set; nothing was changed" >&2; return 1;;
  esac

  echo "waiting for $name at $address"
  local waited=0
  while (( waited < 60 )); do
    nc -z -w 3 "$address" 22 >/dev/null 2>&1 && break
    sleep 3; waited=$(( waited + 3 ))
  done
  if (( waited >= 60 )); then
    echo "error: $name never answered at $address. Its running config may carry the new" >&2
    echo "       address without the save, so a reboot returns it to where it was." >&2
    return 1
  fi

  # Something answering at the right address is not proof the right switch is
  # there, nor that the address was actually set rather than already taken by
  # something else. Both are checked before anything is written to flash, in the
  # same session as the save so it costs one connection rather than two.
  echo "session 2: confirming identity and address, then saving"
  local status=0
  (
    trap switch_close EXIT
    switch_open "$address" "$user" "$key" || exit 10
    switch_run "show system-info" 30 || exit 11
    printf '%s' "$SWITCH_OUTPUT" | tr -d '\r' | grep -qE "System Name[[:space:]]*-[[:space:]]*$name([[:space:]]|\$)" || exit 20
    switch_run "$RUNNING_CONFIG" 90 || exit 12
    printf '%s' "$SWITCH_OUTPUT" | tr -d '\r' | grep -qF "ip address $address $netmask" || exit 21
    switch_run "copy running-config startup-config" 60 || exit 13
    # Session one could not log out, because changing the address is what ended
    # it, so its line is still held and counts against the five concurrent
    # clients. Saved already, so none of this is fatal.
    if switch_run "show users" 20; then
      leaked="$(printf '%s' "$SWITCH_OUTPUT" | fleet_predecessor_line)"
      if [ -n "$leaked" ] && switch_run "clear line $leaked" 20; then
        echo "cleared line $leaked, which session one left behind"
      fi
    fi
  ) || status=$?
  case "$status" in
    0)  ;;
    20) echo "error: something answers at $address but it is not $name. Nothing was saved." >&2
        echo "       Check what owns that address before going further." >&2
        return 1;;
    21) echo "error: $name is reachable at $address but its running config does not carry" >&2
        echo "       'ip address $address $netmask'. The change did not take. Nothing was saved." >&2
        return 1;;
    13) echo "error: $name is at $address but the save failed; a reboot will undo it" >&2
        return 1;;
    *)  echo "error: could not verify $name at $address ($status); nothing was saved" >&2
        return 1;;
  esac
  echo "$name is back at $address and saved. Confirm with:"
  echo "  mise run rack:fleet preflight $name"
}

# Put what a preflight saw into the switch's RackSwitch status.
#
# Reported against the configRevision it was measured with, so a status can
# never be read as applying to a revision it did not see. Run by an operator,
# not by a loop: observing costs a connection, and a switch has about seven per
# boot, so an hourly check would take one out daily without changing anything.
#
# Status only. Nothing here changes a switch, and nothing in the cluster changes
# one either; `apply` and `replace` stay deliberate.
cmd_publish() {
  # The rack's objects live in the namespace its site definition names, in the
  # cluster --context names; publishing into whatever context happens to be
  # current could put a staging rack's status into production.
  local name="${1:-}" namespace context="" dry_run=0
  namespace="$(jq -r '.kubernetes.namespace // "tuist"' "$(site_file)")"
  while (( $# )); do
    case "$1" in
      --dry-run) dry_run=1; shift;;
      --namespace) namespace="${2:-}"; shift 2;;
      --context) context="${2:-}"; shift 2;;
      -*) echo "unknown flag: $1" >&2; return 2;;
      *) name="$1"; shift;;
    esac
  done
  [ -n "$name" ] || { echo "usage: rack:fleet publish <device> [--context <kube context>] [--dry-run]" >&2; return 2; }
  fleet_device "$(site_file)" "$name" >/dev/null || return 1

  local address revision drift reachable connections verified status=0
  address="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .mgmt_address' "$(site_file)")"
  revision="$(fleet_config_revision "$(site_file)" "$name")"
  verified="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local report
  report="$(mktemp)"
  if cmd_preflight "$name" > "$report" 2>&1; then
    drift=none; reachable=true
  elif grep -q 'drifted' "$report"; then
    drift=drifted; reachable=true
  else
    drift=unknown; reachable=false
  fi
  # Guarded because the switch being unreachable is exactly when this line is
  # absent, and exactly when the status is worth publishing. An unguarded grep
  # under `set -e` exits here instead, so reachable=false was never recorded.
  connections="$(grep -oE 'connection [0-9]+ since boot' "$report" | head -1 | grep -oE '[0-9]+' || true)"
  sed 's/^/  /' "$report"
  rm -f "$report"

  local patch
  patch="$(jq -n --arg r "$revision" --arg d "$drift" --argjson reach "$reachable" \
                 --arg v "$verified" --argjson c "${connections:-0}" --arg a "$address" '
    { status: { observedRevision: $r, drift: $d, reachable: $reach, lastVerified: $v,
                connectionsUsedSinceBoot: $c,
                message: ("observed at " + $a + " by rack:fleet publish") } }')"

  echo ""
  if (( dry_run )); then
    echo "would patch rackswitch/$name status in namespace $namespace:"
    printf '%s\n' "$patch" | yq -P - | sed 's/^/  /'
    return 0
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "error: kubectl is needed to publish; --dry-run prints the patch instead" >&2
    return 1
  fi
  kubectl ${context:+--context "$context"} -n "$namespace" patch rackswitch "$name" \
    --type merge --subresource status -p "$patch" || status=$?
  if (( status )); then
    echo "error: could not patch rackswitch/$name. The observation above still stands;" >&2
    echo "       only recording it in the cluster failed." >&2
    return "$status"
  fi
  echo "published $name: drift=$drift reachable=$reachable revision=$revision"
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
  fleet_lock "replace $name" || return 1

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
  if ! fleet_has_login "$merged"; then
    echo "error: the merged configuration has no login in it. Refusing to push a file that" >&2
    echo "       would lock everyone out of $name." >&2
    return 1
  fi

  echo ""
  echo "$name would change:"
  if fleet_diff "$current" "$merged" "live/$name" "rendered/$name"; then
    echo "  nothing; the switch already matches the rendered configuration"
  fi

  # The unmanaged list is evidence from one switch, not a fleet law, so every
  # line this would delete is named rather than trusted to be intentional. A
  # line only this device has, that the render does not model and the list does
  # not cover, shows up here instead of disappearing on the next reboot.
  local removals declared undeclared
  removals="$(fleet_removed_lines "$current" "$merged")"
  declared="$(printf '%s\n' "$removals" | awk -F'\t' '$1 == "declared" { printf "  - [%s] %s\n", ($2 == "" ? "global" : $2), $3 }')"
  undeclared="$(printf '%s\n' "$removals" | awk -F'\t' '$1 == "undeclared" { printf "  - [%s] %s\n", ($2 == "" ? "global" : $2), $3 }')"

  if [ -n "$declared" ]; then
    echo ""
    echo "$name loses these because the render says the opposite, which is the change:"
    printf '%s\n' "$declared" | sed 's/^/  - /'
  fi
  if [ -n "$undeclared" ]; then
    echo ""
    echo "!! $name would LOSE these, and the render says nothing about them:"
    printf '%s\n' "$undeclared" | sed 's/^/  - /'
    echo ""
    echo "   That is configuration this switch has and the render does not model. Stop"
    echo "   unless you meant it: add it to the site definition, or to FLEET_UNMANAGED in"
    echo "   lib/config.sh so it is carried across instead of deleted."
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
    if [ -n "$undeclared" ]; then
      read -r -p "replace, DELETING the unaccounted-for lines above? [y/N] " answer
    else
      read -r -p "replace? [y/N] " answer
    fi
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
  [ -n "$command" ] || { echo "usage: mise run rack:fleet <render|preflight|publish|diff|apply|save|replace|backup|drift|ports|locate|recover|sessions|probe-tftp>" >&2; return 2; }
  shift
  [ -f "$(site_file)" ] || { echo "error: no site definition at $(site_file)" >&2; return 2; }
  fleet_load_jumps "$(site_file)"
  fleet_load_logins "$(site_file)"
  case "$command" in
    render)     cmd_render "$@";;
    diff)       cmd_diff "$@";;
    apply)      refuse_adopted "$@" && cmd_apply "$@";;
    backup)     cmd_backup "$@";;
    save)       refuse_adopted "$@" && cmd_save "$@";;
    sessions)   cmd_sessions "$@";;
    preflight)  cmd_preflight "$@";;
    publish)    cmd_publish "$@";;
    ports)      cmd_ports "$@";;
    locate)     cmd_locate "$@";;
    recover)    refuse_adopted "$@" && cmd_recover "$@";;
    replace)    refuse_adopted "$@" && cmd_replace "$@";;
    drift)      cmd_drift "$@";;
    probe-tftp) cmd_probe_tftp "$@";;
    *) echo "unknown command: $command" >&2; return 2;;
  esac
}

main "$@"
