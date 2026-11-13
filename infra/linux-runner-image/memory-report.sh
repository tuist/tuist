#!/usr/bin/env bash
# ACTIONS_RUNNER_HOOK_JOB_COMPLETED: tells the job's author, in the GitHub
# UI, when the job ran the runner VM out of memory or came close.
#
# Without it, a job that fills the VM shows only the processes the kernel
# killed: a step exiting 137, or, before the dind sidecar put job containers
# first in line for the OOM killer, a runner that "lost communication with
# the server". Neither names memory as the cause.
#
# Reads three things, all best-effort:
#   - /proc/vmstat oom_kill: the guest kernel's kill count, any container.
#     A Pod runs one job, so every kill belongs to this one.
#   - the lowest MemAvailable vitals.sh saw during the job.
#   - the victim the dind sidecar read from the kernel log, which this
#     unprivileged container cannot read itself (cache-volume pools only).
# Always exits 0: a failing job-completed hook fails the job.
set -u

vmstat="${TUIST_RUNNER_VMSTAT:-/proc/vmstat}"
low_file="${TUIST_RUNNER_MEMORY_LOW_FILE:-/tmp/tuist-runner-memory-low}"
dind_file="${TUIST_RUNNER_DIND_MEMORY_FILE:-/var/run/tuist-dind-memory}"
advice="lower the memory the build uses, such as the number of parallel jobs or test forks, or run the job on a runner with more memory"
jvm_advice="lower the JVM heap the build uses (org.gradle.jvmargs, kotlin.daemon.jvmargs) or the number of parallel test forks, or run the job on a runner with more memory"

# kB as GB with one decimal, the unit runner shapes are named in.
gb() { awk -v kb="$1" 'BEGIN { printf "%.1f", kb / 1048576 }'; }
# The value of key=value in a space-separated line.
field() { printf '%s\n' "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1 == k { print $2; exit }'; }

kills="$(awk '$1 == "oom_kill" { print $2 }' "${vmstat}" 2>/dev/null)"
read -r low total 2>/dev/null <"${low_file}" || true

if [ "${kills:-0}" -gt 0 ] 2>/dev/null; then
  dind="$(cat "${dind_file}" 2>/dev/null || true)"
  # The job can write the shared file, so keep only a plain process name.
  victim="$(field "${dind}" oom.victim | tr -cd 'A-Za-z0-9._-')"
  victim_kb="$(field "${dind}" oom.victim.anon.kb | tr -cd '0-9')"
  container="$(field "${dind}" oom.victim.container | tr -cd 'A-Za-z0-9._/:@-')"
  image="$(field "${dind}" oom.victim.image | tr -cd 'A-Za-z0-9._/:@-')"
  named=""
  if [ -n "${victim}" ]; then
    named="${victim}"
    [ -n "${victim_kb}" ] && named="${victim} ($(gb "${victim_kb}") GB)"
    if [ "${container}" = "docker-build" ]; then
      named="${named} in a docker build step"
    elif [ -n "${container}" ]; then
      named="${named} in container ${container}${image:+ (${image})}"
    fi
  fi
  # Only a JVM's heap is worth naming; other processes get general advice.
  [ "${victim}" = "java" ] && advice="${jvm_advice}"
  if [ "${kills}" -eq 1 ]; then
    stopped="${named:-a process}"
  else
    stopped="${kills} processes${named:+, the last one ${named},}"
  fi
  size=""
  [ "${total:-0}" -gt 0 ] 2>/dev/null && size=" The runner has $(gb "${total}") GB of memory."
  echo "::error title=Out of memory::This job ran the runner out of memory, and the Linux kernel stopped ${stopped} to free some.${size} To fit, ${advice}."
elif [ "${total:-0}" -gt 0 ] 2>/dev/null && [ "${low:-}" -ge 0 ] 2>/dev/null && [ $((low * 20)) -lt "${total}" ]; then
  echo "::warning title=Close to the memory limit::This job came within $(gb "${low}") GB of running the runner out of memory ($(gb "${total}") GB). If it runs out, the Linux kernel stops the job's largest process. To leave room, ${advice}."
fi
exit 0
