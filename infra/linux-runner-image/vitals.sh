#!/usr/bin/env bash
# Periodic resource-vitals emitter for the Linux runner.
#
# A runner that dies mid-job ("self-hosted runner lost communication
# with the server") leaves nothing behind: the kata microVM is torn
# down and reaped, and every external vantage point (k8s events, node
# metrics, GitHub) is blind to what happened *inside* the guest. This
# script closes that gap. dispatch-poll.sh launches it in the
# background right before exec'ing the runner, so it samples for the
# job's lifetime and its last line before a death lands in the Pod's
# stdout -> Pod logs -> Loki, surviving the VM.
#
# Each line is tagged RUNNER_VITALS so it filters cleanly in Loki.
# It distinguishes the two leading death modes:
#   - guest OOM           -> oom_kill increments / kmsg.oom line
#   - CPU/mem starvation  -> cpu.psi / mem.psi avg10 climb, mem.current
#                            approaching mem.max
#
# Scope note: the cgroup mem.* / oom_kill fields are THIS (runner)
# container only. The heavy build steps often run in the dind sidecar,
# so vm.mem.* (guest-wide /proc/meminfo), the PSI fields, and the
# /dev/kmsg OOM watcher are what catch a Docker/buildkit OOM or
# starvation living in the sidecar / pod / VM boundary.
#
# Dependency-free and best-effort: unreadable files (PSI disabled in
# the guest kernel, cgroup v1, restricted /dev/kmsg) degrade to empty
# fields, never an error, so this can never block or fail the runner.
# It only runs while a job executes, so idle warm Pods stay quiet.
set -u

# Clamp the interval to a positive integer. A 0, empty, or non-numeric
# value would spin the loop and flood the logs, the opposite of
# fail-open telemetry.
interval="${TUIST_RUNNER_VITALS_INTERVAL:-3}"
if ! [ "${interval}" -ge 1 ] 2>/dev/null; then
  interval=3
fi
cg="/sys/fs/cgroup"

# Read a single cgroup/proc value, stripped of its trailing newline.
field() { [ -r "$1" ] && tr -d '\n' <"$1" 2>/dev/null || true; }

# Guest-wide memory (kB) from /proc/meminfo. Unlike the cgroup memory.*
# fields, which are scoped to this container, /proc/meminfo covers the
# whole microVM, so it reflects the dind sidecar's dockerd/buildkit
# usage too.
meminfo() { awk -v k="$1" '$1==k":"{print $2}' /proc/meminfo 2>/dev/null || true; }

# Pull a named counter out of cgroup v2 memory.events (e.g. oom_kill).
events() {
  [ -r "$cg/memory.events" ] && awk -v k="$1" '$1==k{print $2}' "$cg/memory.events" 2>/dev/null || true
}

# avg10 of a PSI class (some|full) from a /proc/pressure/* file.
psi() {
  [ -r "$1" ] || return 0
  awk -v c="$2" '$1==c{for(i=2;i<=NF;i++){split($i,a,"=");if(a[1]=="avg10")print a[2]}}' "$1" 2>/dev/null || true
}

# Best-effort guest-kernel OOM watcher. Reading /dev/kmsg needs an
# unrestricted guest (kernel.dmesg_restrict=0) or capability; when it
# is readable, an OOM kill shows up here verbatim, which is the
# ground-truth signal. When it is not, the cgroup oom_kill counter
# below is the privilege-free fallback.
if [ -r /dev/kmsg ]; then
  (
    while IFS= read -r line; do
      case "$line" in
        *"oom-kill:"* | *"Out of memory:"* | *"Killed process"*)
          printf '%s RUNNER_VITALS kmsg.oom %s\n' "$(date -u +%FT%TZ)" "${line#*;}"
          ;;
      esac
    done <"/dev/kmsg"
  ) &
fi

while :; do
  printf '%s RUNNER_VITALS vm.mem.total.kb=%s vm.mem.avail.kb=%s mem.current=%s mem.peak=%s mem.max=%s mem.swap=%s oom=%s oom_kill=%s cpu.psi.some.avg10=%s mem.psi.some.avg10=%s mem.psi.full.avg10=%s io.psi.some.avg10=%s load=%s\n' \
    "$(date -u +%FT%TZ)" \
    "$(meminfo MemTotal)" \
    "$(meminfo MemAvailable)" \
    "$(field "$cg/memory.current")" \
    "$(field "$cg/memory.peak")" \
    "$(field "$cg/memory.max")" \
    "$(field "$cg/memory.swap.current")" \
    "$(events oom)" \
    "$(events oom_kill)" \
    "$(psi /proc/pressure/cpu some)" \
    "$(psi /proc/pressure/memory some)" \
    "$(psi /proc/pressure/memory full)" \
    "$(psi /proc/pressure/io some)" \
    "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null | tr ' ' ',')"
  sleep "$interval"
done
