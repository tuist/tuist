#!/bin/bash
# Sources logd-watchdog.sh and drives watchdog_tick against a scripted logd.
# `ps` is a stand-in, so the test runs on macOS and Linux alike.
# shellcheck disable=SC2034
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }

# shellcheck source=logd-watchdog.sh
source "$ROOT/logd-watchdog.sh"
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT

# The scripted logd: its pid, and its cumulative CPU in centiseconds.
ps() {
  printf '    1     0:01.00 launchd\n'
  [ -n "${logd_pid}" ] || return 0
  printf '  %s %d:%02d.%02d logd\n' "${logd_pid}" $((logd_cpu / 6000)) $((logd_cpu / 100 % 60)) $((logd_cpu % 100))
}

setup() {
  work=$(mktemp -d "$base/test.XXXXXX")
  logd_pid=300
  logd_cpu=0
  LOGD_WATCHDOG_INTERVAL=30
  LOGD_WEDGED_PERCENT=50
  LOGD_WEDGED_SAMPLES=10
  LOGD_WEDGED_MARKER="${work}/logd-wedged"
  prev_pid=""
  prev_cpu=0
  hot_samples=0
  watchdog_tick >/dev/null || fail 'the first sample reported a wedge'
}

# spend PERCENT runs one interval in which logd uses PERCENT of a core, then
# ticks in this shell, leaving what the tick logged in $out and its status in
# $rc.
spend() {
  logd_cpu=$((logd_cpu + $1 * LOGD_WATCHDOG_INTERVAL))
  watchdog_tick >"${work}/out"
  rc=$?
  out=$(cat "${work}/out")
}

test_ps_cpu_times_are_parsed() {
  eq 12 "$(cpu_centiseconds 0:00.12)"
  eq 473182 "$(cpu_centiseconds 78:51.82)"
  eq 372345 "$(cpu_centiseconds 1:02:03.45)"
  eq 18000000 "$(cpu_centiseconds 2-02:00:00.00)"
  eq 6100 "$(cpu_centiseconds 01:01)"
}

test_a_logd_spinning_for_five_minutes_is_reported() {
  setup
  for _ in 1 2 3 4 5 6 7 8 9; do
    spend 85
    eq 0 "${rc}"
    eq "" "${out}"
  done
  [ ! -e "${LOGD_WEDGED_MARKER}" ] || fail 'reported after nine hot samples'
  spend 85
  eq 1 "${rc}"
  [ -s "${LOGD_WEDGED_MARKER}" ] || fail 'no wedged marker'
  [[ "${out}" == *"logd (pid 300) used at least 50% of a core for 300s (last 85%); reporting it wedged"* ]] || fail "unexpected log: ${out}"
}

test_a_busy_minute_is_not_a_wedge() {
  setup
  for percent in 90 90 90 90 90 90 90 90 90 10 90 90 90 90 90 90 90 90 90; do
    spend "${percent}"
    eq 0 "${rc}"
  done
  [ ! -e "${LOGD_WEDGED_MARKER}" ] || fail 'reported a logd that cooled down'
}

test_a_healthy_logd_is_never_reported() {
  setup
  for _ in $(seq 1 40); do
    spend 1
    eq 0 "${rc}"
  done
  [ ! -e "${LOGD_WEDGED_MARKER}" ] || fail 'reported a healthy logd'
}

test_a_new_logd_starts_a_new_count() {
  setup
  for _ in 1 2 3 4 5 6 7 8 9; do
    spend 85
  done
  logd_pid=400
  spend 85
  eq 0 "${rc}"
  [ ! -e "${LOGD_WEDGED_MARKER}" ] || fail 'counted samples across two logd processes'
}

test_no_logd_is_not_an_error() {
  setup
  logd_pid=""
  out=$(watchdog_tick) || fail 'tick failed without a logd'
  eq "" "${out}"
}

for test in $(declare -F | awk '{print $3}' | grep '^test_'); do
  "$test"
  echo "ok: $test"
done
