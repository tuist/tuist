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
#   - guest OOM           -> vm.oom_kill / oom_kill increment, kmsg.oom line
#   - CPU/mem starvation  -> cpu.psi / mem.psi avg10 climb, mem.current
#                            approaching mem.max
#
# Scope note: the cgroup mem.* / oom_kill fields are THIS (runner)
# container only. The heavy build steps often run in the dind sidecar,
# so vm.mem.* (guest-wide /proc/meminfo, broken down into anon, page
# cache, shmem, dirty and slab so a full guest says what filled it),
# dind.* (the sidecar's cgroup, job containers included, which
# tuist-cache-volume publishes to $dind_file on cache-volume pools),
# the PSI fields, and the /dev/kmsg OOM watcher are what catch a
# Docker/buildkit OOM or starvation living in the sidecar / pod / VM
# boundary.
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

# The dind sidecar's cgroup memory, one line of dind.* fields that
# tuist-cache-volume rewrites every 3s on the shared /var/run volume.
dind_file="/var/run/tuist-dind-memory"

# Guest-wide memory (kB) from /proc/meminfo, as vm.mem.<name>.kb fields.
# Unlike the cgroup memory.* fields, which are scoped to this container,
# /proc/meminfo covers the whole microVM, so it reflects the dind
# sidecar's dockerd/buildkit usage too. total and avail come first and
# keep their names; a key the kernel lacks is omitted.
vm_mem() {
  awk '
    BEGIN {
      n = split("MemTotal:total MemAvailable:avail MemFree:free Cached:cached AnonPages:anon Shmem:shmem Dirty:dirty Writeback:writeback SReclaimable:slab.reclaimable SUnreclaim:slab.unreclaimable PageTables:pagetables", m, " ")
      for (i = 1; i <= n; i++) { split(m[i], kv, ":"); key[i] = kv[1] ":"; name[i] = kv[2] }
    }
    { v[$1] = $2 }
    END {
      for (i = 1; i <= n; i++) if (key[i] in v) printf "%svm.mem.%s.kb=%s", (out++ ? " " : ""), name[i], v[key[i]]
    }' /proc/meminfo 2>/dev/null || true
}

# The lowest guest-wide MemAvailable this job reached, as "<avail kB>
# <total kB>", for memory-report.sh, the job-completed hook. A dip
# between two samples is missed; the OOM-kill count is not.
low_file="${TUIST_RUNNER_MEMORY_LOW_FILE:-/tmp/tuist-runner-memory-low}"
low_avail=""

# Pull a named counter out of cgroup v2 memory.events (e.g. oom_kill).
events() {
  [ -r "$cg/memory.events" ] && awk -v k="$1" '$1==k{print $2}' "$cg/memory.events" 2>/dev/null || true
}

# avg10 of a PSI class (some|full) from a /proc/pressure/* file.
psi() {
  [ -r "$1" ] || return 0
  awk -v c="$2" '$1==c{for(i=2;i<=NF;i++){split($i,a,"=");if(a[1]=="avg10")print a[2]}}' "$1" 2>/dev/null || true
}

# Total and idle jiffies from /proc/stat's aggregate cpu line. Diffed
# between samples to derive guest-wide CPU-busy%, the CPU-starvation
# signal that works even when the guest kernel doesn't expose PSI.
cpu_times() { awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; print t, $5+$6; exit}' /proc/stat 2>/dev/null; }

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

# CPU baseline so the first sample has a prior to diff against.
cur="$(cpu_times)"
prev_total="${cur%% *}"
prev_idle="${cur##* }"

while :; do
  # Guest-wide CPU-busy% over the interval (all vCPUs), from /proc/stat
  # deltas. Reliable CPU-starvation signal independent of PSI.
  cur="$(cpu_times)"
  cur_total="${cur%% *}"
  cur_idle="${cur##* }"
  cpu_busy=""
  if [ -n "${cur_total}" ] && [ -n "${prev_total}" ] && [ "${cur_total}" -gt "${prev_total}" ] 2>/dev/null; then
    cpu_busy="$(awk -v t="$((cur_total - prev_total))" -v i="$((cur_idle - prev_idle))" 'BEGIN{printf "%d", (t>0)?(1-i/t)*100:0}')"
  fi
  prev_total="${cur_total}"
  prev_idle="${cur_idle}"

  line="$(date -u +%FT%TZ) RUNNER_VITALS"
  mem="$(vm_mem)"
  line="${line} ${mem}"
  # Processes the guest kernel killed for memory, in any container.
  line="${line} vm.oom_kill=$(awk '$1=="oom_kill"{print $2}' /proc/vmstat 2>/dev/null)"
  avail="${mem#*vm.mem.avail.kb=}"
  avail="${avail%% *}"
  total="${mem#vm.mem.total.kb=}"
  total="${total%% *}"
  if [ "${avail}" -ge 0 ] 2>/dev/null && [ "${total}" -gt 0 ] 2>/dev/null &&
    { [ -z "${low_avail}" ] || [ "${avail}" -lt "${low_avail}" ]; }; then
    low_avail="${avail}"
    printf '%s %s\n' "${avail}" "${total}" >"${low_file}" 2>/dev/null || true
  fi
  line="${line} mem.current=$(field "$cg/memory.current") mem.peak=$(field "$cg/memory.peak") mem.max=$(field "$cg/memory.max") mem.swap=$(field "$cg/memory.swap.current")"
  line="${line} oom=$(events oom) oom_kill=$(events oom_kill)"
  # dind.age.s says how stale the sidecar's last write is: a sidecar
  # that died or stalled leaves its final sample behind.
  if [ -r "${dind_file}" ]; then
    line="${line} $(field "${dind_file}") dind.age.s=$(($(date +%s) - $(stat -c %Y "${dind_file}" 2>/dev/null || date +%s)))"
  fi
  [ -n "${cpu_busy}" ] && line="${line} cpu.busy.pct=${cpu_busy}"
  # PSI fields only when the guest kernel exposes them (psi=1 on the
  # kata cmdline). Omitted otherwise so we don't log empty noise.
  v="$(psi /proc/pressure/cpu some)" && [ -n "${v}" ] && line="${line} cpu.psi.some.avg10=${v}"
  v="$(psi /proc/pressure/memory some)" && [ -n "${v}" ] && line="${line} mem.psi.some.avg10=${v}"
  v="$(psi /proc/pressure/memory full)" && [ -n "${v}" ] && line="${line} mem.psi.full.avg10=${v}"
  v="$(psi /proc/pressure/io some)" && [ -n "${v}" ] && line="${line} io.psi.some.avg10=${v}"
  line="${line} load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null | tr ' ' ',')"

  printf '%s\n' "${line}"
  sleep "${interval}"
done
