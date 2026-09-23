# shellcheck shell=bash
# The rack lock and the hold a pending rollback puts on it. Sourced by fleet.sh
# and omada.sh, since every change to a rack's switches goes through one lock,
# whichever path makes it. Expects SITE to name the rack.

# How long after its timer fires a switch is given to come back before its
# rollback can be declared over; fleet.sh's wait_for_reboot allows the same.
ROLLBACK_BOOT_MARGIN=300

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
#
# A rollback that may still be pending holds the rack past the run that left it;
# see rollback_hold in fleet.sh. Every acquisition refuses while that hold is
# there, except the one `resolve` takes to lift it.
FLEET_LOCK=""

fleet_lock() {
  local reason="$1" during_hold="${2:-}" dir owner pid
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
    # Read under the lock, because the run that leaves a hold writes it before
    # letting go.
    if [ -z "$during_hold" ] && [ -f "$(rollback_record)" ]; then
      rollback_report >&2
      fleet_unlock
      return 1
    fi
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

# The hold a pending rollback puts on the rack.
#
# A reboot timer that was armed and not confirmed cancelled leaves the switch
# minutes from rebooting, and a switch whose running configuration already
# matches the render passes the apply ordering. Releasing the lock at that point
# would let the next ToR be changed while this one goes down, which is exactly
# the "never both ToRs at once" the lock exists for. So the run that leaves a
# rollback pending records it, beside the lock and while still holding it, and
# the rack stays held until `resolve` has seen the switch back on its saved
# configuration. Nothing lifts it on its own: a later run cannot tell a rollback
# that finished from one still to come.
rollback_record() { echo "${FLEET_LOCK_DIR:-/tmp}/rack-fleet-$SITE.rollback"; }
rollback_field()  { awk -v key="$1" '$1 == key { print $2 }' "$(rollback_record)"; }

# An epoch as local time: BSD date takes it with -r, GNU date with -d @.
local_time() { date -r "$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M:%S'; }

rollback_report() {
  local device address armed fires
  device="$(rollback_field device)"
  address="$(rollback_field address)"
  armed="$(rollback_field armed)"
  fires="$(rollback_field fires)"
  echo "error: $device may still be rolling back. Its reboot timer was armed at $(local_time "$armed")"
  echo "       and never confirmed cancelled, so it reboots on its saved configuration by"
  echo "       $(local_time "$fires"). Nothing else in $SITE is changed until that is over."
  echo "       Once $device ($address) is back, from $(local_time $(( fires + ROLLBACK_BOOT_MARGIN ))), confirm it with:"
  echo "         mise run rack:fleet resolve $device"
}
