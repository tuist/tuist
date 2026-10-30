#!/bin/bash
# Restarts the guest's logd when it wedges. Runs as root from the
# dev.tuist.logd-watchdog LaunchDaemon for the life of the VM, so it covers the
# warm standby and the job alike.
#
# A wedged logd spins on one core and stops draining the processes' log
# buffers. A process whose buffer fills then blocks inside os_log, including
# syspolicyd while it holds the lock Xcode's execution-policy registrations
# wait on, so a build stops with no compiler running. SIGKILL recovers it:
# launchd starts a new logd and the blocked writers carry on. SIGTERM does not:
# logd stays up, still not draining, and sudo starts blocking too, which is why
# this runs as root instead of going through sudo.
#
# Wedged is logd using LOGD_WEDGED_PERCENT of one core in each of
# LOGD_WEDGED_SAMPLES consecutive samples. A healthy guest's logd stays near 1%
# of a core, including under a heavy build.
#
# A logd that launchd does not bring back is reported by writing
# LOGD_WEDGED_MARKER. In the status share, tart-kubelet reads it and stops the
# VM; dispatch-poll.sh reads it while the VM is warm and stops polling for a
# job.

set -uo pipefail

STATUS_SHARE="/Volumes/My Shared Files/status"
LOGD_WATCHDOG_INTERVAL="${LOGD_WATCHDOG_INTERVAL:-30}"
LOGD_WEDGED_PERCENT="${LOGD_WEDGED_PERCENT:-50}"
LOGD_WEDGED_SAMPLES="${LOGD_WEDGED_SAMPLES:-4}"
LOGD_RESTART_TIMEOUT="${LOGD_RESTART_TIMEOUT:-10}"
LOGD_WATCHDOG_LOG="${LOGD_WATCHDOG_LOG:-/var/log/tuist-runner/poll.log}"

# say appends a line to dispatch-poll.sh's log, which reaches the host as the
# runner log, or to stdout before dispatch-poll.sh has created it. Never
# creates the log: it belongs to `runner`, and a root-owned one would lock
# dispatch-poll.sh out.
say() {
  local line
  line="$(date -u +%FT%TZ) logd-watchdog: $*"
  if [ -f "${LOGD_WATCHDOG_LOG}" ]; then
    echo "${line}" >>"${LOGD_WATCHDOG_LOG}"
  else
    echo "${line}"
  fi
}

# wedged_marker prints where to report a logd that cannot be recovered.
wedged_marker() {
  if [ -n "${LOGD_WEDGED_MARKER:-}" ]; then
    echo "${LOGD_WEDGED_MARKER}"
  elif [ -d "${STATUS_SHARE}" ]; then
    echo "${STATUS_SHARE}/logd-wedged"
  else
    echo /tmp/tuist-logd-wedged
  fi
}

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

# restart_logd kills logd ($1) and prints the pid launchd starts in its place,
# or fails when none comes up within LOGD_RESTART_TIMEOUT seconds.
restart_logd() {
  local pid="$1" sample waited=0
  kill -KILL "${pid}" 2>/dev/null || return 1
  while [ "${waited}" -lt "${LOGD_RESTART_TIMEOUT}" ]; do
    sleep 1
    waited=$((waited + 1))
    sample=$(logd_sample)
    if [ -n "${sample}" ] && [ "${sample%% *}" != "${pid}" ]; then
      echo "${sample%% *}"
      return 0
    fi
  done
  return 1
}

prev_pid=""
prev_cpu=0
hot_samples=0
restarts=0

# report_wedged writes the marker the host stops the VM on.
report_wedged() {
  local marker
  marker=$(wedged_marker)
  date -u +%FT%TZ >"${marker}" 2>/dev/null || true
  say "$*; reported in ${marker} for the host to stop the VM"
}

# watchdog_tick takes one sample and restarts logd once it has been wedged for
# LOGD_WEDGED_SAMPLES samples in a row. Returns 1 once logd is reported as
# unrecoverable, after which there is nothing left to do.
watchdog_tick() {
  local sample pid cpu percent new_pid
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

  hot_samples=0
  restarts=$((restarts + 1))
  say "logd (pid ${pid}) used at least ${LOGD_WEDGED_PERCENT}% of a core for $((LOGD_WEDGED_SAMPLES * LOGD_WATCHDOG_INTERVAL))s (last ${percent}%); killing it (restart ${restarts})"
  if ! new_pid=$(restart_logd "${pid}"); then
    report_wedged "logd (pid ${pid}) did not come back within ${LOGD_RESTART_TIMEOUT}s"
    return 1
  fi
  say "logd restarted (pid ${new_pid})"
}

main() {
  say "watching logd every ${LOGD_WATCHDOG_INTERVAL}s"
  while watchdog_tick; do
    sleep "${LOGD_WATCHDOG_INTERVAL}"
  done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main
fi
