#!/bin/bash
# Sources logd-watchdog.sh and drives watchdog_tick against a scripted logd.
# `ps`, `kill` and `sleep` are stand-ins, so the test signals nothing and runs
# on macOS and Linux alike.
# shellcheck disable=SC2034,SC2329
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }

# shellcheck source=logd-watchdog.sh
source "$ROOT/logd-watchdog.sh"
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT

# The scripted logd: its pid and cumulative CPU in centiseconds live in files,
# because restart_logd runs in a command substitution.
ps() {
  local cpu
  printf '    1     0:01.00 launchd\n'
  [ -s "${work}/pid" ] || return 0
  cpu=$(cat "${work}/cpu")
  printf '  %s %d:%02d.%02d logd\n' "$(cat "${work}/pid")" $((cpu / 6000)) $((cpu / 100 % 60)) $((cpu % 100))
}

# A stand-in for kill: records the signal, and launchd starts a new logd unless
# RESPAWN is 0.
kill() {
  echo "$*" >>"${work}/kills"
  if [ "${RESPAWN}" = 1 ]; then
    echo $(($(cat "${work}/pid") + 1)) >"${work}/pid"
    echo 0 >"${work}/cpu"
  else
    : >"${work}/pid"
  fi
}

sleep() { :; }

# The real probe is exercised on its own below; ticks read a scripted outcome.
eval "real_$(declare -f probe_logging)"
probe_logging() { [ "$(cat "${work}/probe")" = ok ]; }

setup() {
  work=$(mktemp -d "$base/test.XXXXXX")
  echo 300 >"${work}/pid"
  echo 0 >"${work}/cpu"
  echo ok >"${work}/probe"
  RESPAWN=1
  LOGD_WATCHDOG_INTERVAL=30
  LOGD_WEDGED_PERCENT=50
  LOGD_WEDGED_SAMPLES=4
  LOGD_PROBE_TIMEOUT=10
  LOGD_STALLED_SAMPLES=2
  LOGD_RESTART_TIMEOUT=10
  LOGD_WEDGED_MARKER="${work}/logd-wedged"
  LOGD_WATCHDOG_LOG="${work}/poll.log"
  : >"${LOGD_WATCHDOG_LOG}"
  prev_pid=""
  prev_cpu=0
  hot_samples=0
  stalled_samples=0
  restarts=0
  watchdog_tick || fail 'the first sample reported a wedge'
}

# spend PERCENT runs one interval in which logd uses PERCENT of a core, then
# ticks in this shell, leaving its status in $rc.
spend() {
  echo $(($(cat "${work}/cpu") + $1 * LOGD_WATCHDOG_INTERVAL)) >"${work}/cpu"
  watchdog_tick
  rc=$?
}

log() { cat "${LOGD_WATCHDOG_LOG}"; }

test_ps_cpu_times_are_parsed() {
  eq 12 "$(cpu_centiseconds 0:00.12)"
  eq 473182 "$(cpu_centiseconds 78:51.82)"
  eq 372345 "$(cpu_centiseconds 1:02:03.45)"
  eq 18000000 "$(cpu_centiseconds 2-02:00:00.00)"
  eq 6100 "$(cpu_centiseconds 01:01)"
}

test_a_logd_spinning_for_two_minutes_is_killed_and_watched_again() {
  setup
  for _ in 1 2 3; do
    spend 85
    eq 0 "${rc}"
  done
  [ ! -e "${work}/kills" ] || fail 'killed after three hot samples'
  spend 85
  eq 0 "${rc}"
  eq "-KILL 300" "$(cat "${work}/kills")"
  [[ "$(log)" == *"logd (pid 300) used at least 50% of a core for 120s (last 85%); killing it (restart 1)"* ]] || fail "unexpected log: $(log)"
  [[ "$(log)" == *"logd restarted (pid 301)"* ]] || fail "unexpected log: $(log)"
  [ ! -e "${LOGD_WEDGED_MARKER}" ] || fail 'reported a logd that came back'

  # The new logd is watched from a fresh baseline, and restarted again if it
  # wedges too.
  for _ in 1 2 3 4 5; do
    spend 85
    eq 0 "${rc}"
  done
  eq "-KILL 300
-KILL 301" "$(cat "${work}/kills")"
  [[ "$(log)" == *"logd (pid 301) used at least 50% of a core for 120s (last 85%); killing it (restart 2)"* ]] || fail "unexpected log: $(log)"
}

test_a_logd_that_does_not_come_back_is_reported() {
  setup
  RESPAWN=0
  for _ in 1 2 3 4; do
    spend 85
  done
  eq 1 "${rc}"
  [ -s "${LOGD_WEDGED_MARKER}" ] || fail 'no wedged marker'
  [[ "$(log)" == *"logd (pid 300) did not come back within 10s; reported in ${LOGD_WEDGED_MARKER} for the host to stop the VM"* ]] || fail "unexpected log: $(log)"
}

test_a_busy_minute_is_not_a_wedge() {
  setup
  for percent in 90 90 90 10 90 90 90; do
    spend "${percent}"
    eq 0 "${rc}"
  done
  [ ! -e "${work}/kills" ] || fail 'killed a logd that cooled down'
}

test_a_healthy_logd_is_left_alone() {
  setup
  for _ in $(seq 1 40); do
    spend 1
    eq 0 "${rc}"
  done
  [ ! -e "${work}/kills" ] || fail 'killed a healthy logd'
  eq "" "$(log)"
}

test_a_new_logd_starts_a_new_count() {
  setup
  for _ in 1 2 3; do
    spend 85
  done
  echo 400 >"${work}/pid"
  spend 85
  [ ! -e "${work}/kills" ] || fail 'counted samples across two logd processes'
}

test_no_logd_is_not_an_error() {
  setup
  : >"${work}/pid"
  watchdog_tick || fail 'tick failed without a logd'
}

test_an_idle_logd_that_blocks_writes_is_killed() {
  setup
  echo stalled >"${work}/probe"
  spend 0
  eq 0 "${rc}"
  [ ! -e "${work}/kills" ] || fail 'killed after one blocked write'
  spend 0
  eq 0 "${rc}"
  eq "-KILL 300" "$(cat "${work}/kills")"
  [[ "$(log)" == *"logd (pid 300) left a log write blocked for 10s in 2 samples in a row; killing it (restart 1)"* ]] || fail "unexpected log: $(log)"
  [[ "$(log)" == *"logd restarted (pid 301)"* ]] || fail "unexpected log: $(log)"
}

test_a_blocked_write_that_recovers_is_not_a_wedge() {
  setup
  for probe in stalled ok stalled ok stalled ok; do
    echo "${probe}" >"${work}/probe"
    spend 0
    eq 0 "${rc}"
  done
  [ ! -e "${work}/kills" ] || fail 'killed a logd whose writes recovered'
}

test_an_idle_logd_that_blocks_writes_and_does_not_come_back_is_reported() {
  setup
  RESPAWN=0
  echo stalled >"${work}/probe"
  spend 0
  spend 0
  eq 1 "${rc}"
  [ -s "${LOGD_WEDGED_MARKER}" ] || fail 'no wedged marker'
}

test_the_probe_is_bounded_and_killed() {
  (
    unset -f kill sleep
    LOGD_PROBE_TIMEOUT=1
    logger() { exec sleep 937; }
    started=${SECONDS}
    real_probe_logging && fail 'a blocked write passed the probe'
    [ $((SECONDS - started)) -le 3 ] || fail 'the probe was not bounded'
    pgrep -fx 'sleep 937' >/dev/null && fail 'left the blocked probe running'
    logger() { :; }
    real_probe_logging || fail 'a returning write failed the probe'
  ) || exit 1
}

test_the_runner_log_is_never_created() {
  setup
  rm "${LOGD_WATCHDOG_LOG}"
  out=$(say hello)
  [[ "${out}" == *"logd-watchdog: hello" ]] || fail "unexpected stdout: ${out}"
  [ ! -e "${LOGD_WATCHDOG_LOG}" ] || fail 'created the runner log'
}

for test in $(declare -F | awk '{print $3}' | grep '^test_'); do
  "$test"
  echo "ok: $test"
done
