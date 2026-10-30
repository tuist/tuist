#!/bin/bash
# Reports a wedged logd to the host. Forked by dispatch-poll.sh at boot, so it
# watches the warm standby and the job alike, and dies with the VM.
#
# A wedged logd spins on one core and stops draining the processes' log
# buffers. Every process that logs then blocks inside os_log, including
# syspolicyd while it holds the lock Xcode's execution-policy registrations
# wait on, so a build stops with no compiler running. Nothing in the guest
# recovers it: logd ignores SIGTERM in that state, and sudo, which the guest's
# own halt goes through, blocks too. So this script only reports, without sudo
# or anything else that writes to the unified log, by writing
# LOGD_WEDGED_MARKER. In the status share,
# tart-kubelet reads it and stops the VM; dispatch-poll.sh reads it while the
# VM is warm and stops polling for a job.
#
# Wedged is logd using LOGD_WEDGED_PERCENT of one core in each of
# LOGD_WEDGED_SAMPLES consecutive samples. A healthy guest's logd stays near 1%
# of a core, including under a heavy build.

set -uo pipefail

LOGD_WATCHDOG_INTERVAL="${LOGD_WATCHDOG_INTERVAL:-30}"
LOGD_WEDGED_PERCENT="${LOGD_WEDGED_PERCENT:-50}"
LOGD_WEDGED_SAMPLES="${LOGD_WEDGED_SAMPLES:-10}"
LOGD_WEDGED_MARKER="${LOGD_WEDGED_MARKER:-/tmp/tuist-logd-wedged}"

# cpu_centiseconds converts ps's cumulative CPU time ([[DD-]HH:]MM:SS.cc) to
# centiseconds.
cpu_centiseconds() {
  local value="$1" days=0 seconds=0 field fraction=0
  case "${value}" in
    *-*) days="${value%%-*}"; value="${value#*-}" ;;
  esac
  case "${value}" in
    *.*) fraction="${value##*.}"; value="${value%.*}" ;;
  esac
  local IFS=:
  for field in ${value}; do
    seconds=$((seconds * 60 + 10#${field}))
  done
  echo $(((10#${days} * 86400 + seconds) * 100 + 10#${fraction}))
}

# logd_sample prints logd's pid and cumulative CPU time in centiseconds, or
# nothing when logd is not running.
logd_sample() {
  local pid time
  read -r pid time < <(ps -axo pid=,time=,ucomm= | awk '$3 == "logd" { print $1, $2; exit }')
  [ -n "${pid:-}" ] || return 0
  echo "${pid} $(cpu_centiseconds "${time}")"
}

prev_pid=""
prev_cpu=0
hot_samples=0

# watchdog_tick takes one sample and returns 1 once logd has been wedged for
# LOGD_WEDGED_SAMPLES samples in a row, after writing LOGD_WEDGED_MARKER.
watchdog_tick() {
  local sample pid cpu percent
  sample=$(logd_sample)
  if [ -z "${sample}" ]; then
    prev_pid=""
    hot_samples=0
    return 0
  fi
  pid="${sample%% *}"
  cpu="${sample#* }"
  if [ "${pid}" != "${prev_pid}" ]; then
    prev_pid="${pid}"
    prev_cpu="${cpu}"
    hot_samples=0
    return 0
  fi
  percent=$(((cpu - prev_cpu) / LOGD_WATCHDOG_INTERVAL))
  prev_cpu="${cpu}"
  if [ "${percent}" -lt "${LOGD_WEDGED_PERCENT}" ]; then
    hot_samples=0
    return 0
  fi
  hot_samples=$((hot_samples + 1))
  [ "${hot_samples}" -ge "${LOGD_WEDGED_SAMPLES}" ] || return 0

  echo "$(date -u +%FT%TZ) logd-watchdog: logd (pid ${pid}) used at least ${LOGD_WEDGED_PERCENT}% of a core for $((hot_samples * LOGD_WATCHDOG_INTERVAL))s (last ${percent}%); reporting it wedged"
  date -u +%FT%TZ >"${LOGD_WEDGED_MARKER}" 2>/dev/null || true
  return 1
}

main() {
  echo "$(date -u +%FT%TZ) logd-watchdog: watching logd every ${LOGD_WATCHDOG_INTERVAL}s"
  while watchdog_tick; do
    sleep "${LOGD_WATCHDOG_INTERVAL}"
  done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main
fi
