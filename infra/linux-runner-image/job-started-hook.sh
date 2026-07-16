#!/usr/bin/env bash
# ACTIONS_RUNNER_HOOK_JOB_STARTED — the GitHub Actions runner runs this on the
# runner host just before a job's steps execute. A job has been assigned, so
# this runner must NOT be recycled by the idle-registration watchdog armed in
# run-job.sh: disarm it. Kill the watchdog process and drop the marker file the
# watchdog also checks — belt and suspenders, so a job in flight is never
# interrupted even if the watchdog woke in the same instant.
#
# Always exit 0: a non-zero ACTIONS_RUNNER_HOOK_JOB_STARTED fails the job.
set -u

marker=/tmp/tuist-job-started
pidfile=/tmp/tuist-idle-watchdog.pid

: >"${marker}" 2>/dev/null || true
if [ -f "${pidfile}" ]; then
  kill "$(cat "${pidfile}" 2>/dev/null)" 2>/dev/null || true
fi
exit 0
