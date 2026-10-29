#!/usr/bin/env bash
# Samples the runner microVM's machine metrics (CPU / memory / network
# / disk) every few seconds and POSTs them to the Tuist server so the
# job detail page can chart them.
#
# Runs as a native sidecar in the runner Pod (not the runner/customer
# container): the dispatch SA token is isolated from the customer
# container, so the sampler — trusted code — runs alongside with the
# token mounted and the same VM-wide /proc the runner sees (a kata pod
# is one microVM, so /proc/stat and /proc/net/dev are guest-wide).
# Kubelet stops the sidecar when the runner container exits, ending the
# job.
#
# Auth + addressing mirror dispatch-poll.sh: the Pod's projected SA
# token (audience tuist-runners-dispatch) is the Bearer credential, and
# the endpoint is the dispatch URL with `/dispatch` swapped for
# `/pods/<pod>/metrics`. The server resolves the Pod to its job; an
# unclaimed Pod (warm standby, before a job is claimed) is a no-op
# there. Fail-open: a bad sample or failed POST is skipped, never
# affecting the job.
#
# ## Byte counters and awk
#
# Ubuntu's `awk` is mawk, whose `printf "%d"` saturates at INT_MAX
# (2147483647) and whose bare `print` renders integers above 2^31 in
# OFMT (`%.6g`) scientific notation. Neither can carry a byte count.
# Every byte-valued field here is therefore formatted with `%.0f`,
# which goes through the C double path and is exact to 2^53, and
# counter deltas are computed in bash arithmetic (64-bit) rather than
# in awk.

set -uo pipefail

TOKEN_PATH="${TUIST_RUNNER_TOKEN_PATH:-/var/run/secrets/tuist-runner/token}"
DISK_PATH="${TUIST_RUNNER_DISK_PATH:-/var/lib/tuist-runner}"
MEMINFO_PATH=/proc/meminfo
STAT_PATH=/proc/stat
NET_DEV_PATH=/proc/net/dev
interval="${TUIST_RUNNER_METRICS_INTERVAL:-15}"

log() { echo "$(date -u +%FT%TZ) metrics-sampler: $*"; }

# read_cpu echoes "total idle_all iowait" jiffies from /proc/stat's
# aggregate cpu line (idle_all = idle + iowait).
read_cpu() {
  awk '/^cpu / { total = 0; for (i = 2; i <= NF; i++) total += $i; print total, $5 + $6, $6; exit }' "${1:-${STAT_PATH}}"
}

# mem_totals echoes "used total" bytes for the guest.
#
# Both values come from one read of the file. kata boots the sandbox
# at its default size and hot-plugs it up to the shape's configured
# memory, so MemTotal grows during the Pod's life — pairing a MemTotal
# read at sidecar start with a live MemAvailable reports the boot-time
# size forever and drives `used` negative once the guest grows. Reading
# the pair together is what keeps the two consistent, so keep them in
# this single pass.
mem_totals() {
  awk '
    /^MemTotal:/ { total = $2 }
    /^MemAvailable:/ { avail = $2 }
    END { printf "%.0f %.0f", (total - avail) * 1024, total * 1024 }' "${1:-${MEMINFO_PATH}}" 2>/dev/null
}

# disk_totals echoes "used total" bytes for the filesystem backing the
# given path. `-P` keeps df to one line per filesystem, which NR == 2
# relies on.
disk_totals() {
  df -k -P "${1:-${DISK_PATH}}" 2>/dev/null | awk 'NR == 2 { printf "%.0f %.0f", $3 * 1024, $2 * 1024 }'
}

# net_totals echoes cumulative "rx tx" bytes summed over every
# non-loopback interface in /proc/net/dev. Split on the `:` after the
# interface name, then on whitespace — robust across awk variants
# (the counters are the 1st (rx bytes) and 9th (tx bytes) numeric
# fields after the name).
net_totals() {
  awk -F: '
    NR > 2 {
      iface = $1; gsub(/[ \t]/, "", iface)
      if (iface == "lo") next
      split($2, v, " ")
      rx += v[1]; tx += v[9]
    }
    END { printf "%.0f %.0f", rx + 0, tx + 0 }' "${1:-${NET_DEV_PATH}}" 2>/dev/null
}

# delta cur prev -> max(0, cur-prev); a counter reset reports 0.
delta() {
  local d=$(( $1 - $2 ))
  if [ "${d}" -lt 0 ]; then d=0; fi
  printf '%d' "${d}"
}

# metrics_payload TS CPU IOWAIT NET_IN NET_OUT
#
# Reads memory and disk itself so every sample carries a view taken at
# the same moment as the CPU window it is paired with.
metrics_payload() {
  local ts="$1" cpu="$2" iowait="$3" net_in="$4" net_out="$5"
  local mem_used mem_total disk_used disk_total

  read -r mem_used mem_total <<<"$(mem_totals)"
  read -r disk_used disk_total <<<"$(disk_totals)"

  printf '{"samples":[{"timestamp":%s,"cpu_usage_percent":%s,"cpu_iowait_percent":%s,"memory_used_bytes":%s,"memory_total_bytes":%s,"network_bytes_in":%s,"network_bytes_out":%s,"disk_used_bytes":%s,"disk_total_bytes":%s}]}' \
    "${ts}" "${cpu:-0}" "${iowait:-0}" "${mem_used:-0}" "${mem_total:-0}" \
    "${net_in}" "${net_out}" "${disk_used:-0}" "${disk_total:-0}"
}

main() {
  if [ -z "${TUIST_RUNNER_DISPATCH_URL:-}" ] || [ -z "${TUIST_RUNNER_POD_NAME:-}" ]; then
    log "dispatch URL or pod name unset; not sampling"
    exit 0
  fi

  local metrics_url="${TUIST_RUNNER_DISPATCH_URL%/dispatch}/pods/${TUIST_RUNNER_POD_NAME}/metrics"

  # The sidecar starts at Pod boot, but a warm-standby Pod has no job
  # yet — sampling then would just no-op against the server and add load
  # for every idle Pod. The poller stages the JIT here the instant a job
  # is claimed, so wait for it: sampling then spans exactly the job, the
  # same window the macOS sampler covers.
  local jit_path="${TUIST_RUNNER_JIT_PATH:-/var/lib/tuist-runner/jit}"
  log "waiting for a claimed job (JIT at ${jit_path}) before sampling"
  while [ ! -f "${jit_path}" ]; do sleep 1; done

  log "job claimed; sampling every ${interval}s -> ${metrics_url}"

  local prev_rx="" prev_tx=""
  local ts t1 i1 w1 t2 i2 w2 cpu iowait rx tx net_in net_out token payload

  while true; do
    ts="$(date +%s)"

    # CPU over a short in-loop window so the first sample is real (not 0).
    read -r t1 i1 w1 <<<"$(read_cpu)"
    sleep 1
    read -r t2 i2 w2 <<<"$(read_cpu)"
    read -r cpu iowait <<<"$(awk -v t1="${t1:-0}" -v i1="${i1:-0}" -v w1="${w1:-0}" -v t2="${t2:-0}" -v i2="${i2:-0}" -v w2="${w2:-0}" '
      BEGIN {
        dt = t2 - t1
        if (dt <= 0) { print "0 0"; exit }
        busy = dt - (i2 - i1)
        cpu = busy * 100 / dt
        io = (w2 - w1) * 100 / dt
        if (cpu < 0) cpu = 0; if (cpu > 100) cpu = 100
        if (io < 0) io = 0; if (io > 100) io = 100
        printf "%.1f %.1f", cpu, io
      }')"

    read -r rx tx <<<"$(net_totals)"
    if [ -n "${prev_rx}" ]; then
      net_in="$(delta "${rx:-0}" "${prev_rx}")"
      net_out="$(delta "${tx:-0}" "${prev_tx}")"
    else
      net_in=0
      net_out=0
    fi
    prev_rx="${rx:-0}"
    prev_tx="${tx:-0}"

    token="$(cat "${TOKEN_PATH}" 2>/dev/null || true)"
    if [ -z "${token}" ]; then
      log "SA token unreadable at ${TOKEN_PATH}; skipping POST"
      sleep "${interval}"
      continue
    fi

    payload="$(metrics_payload "${ts}" "${cpu:-0}" "${iowait:-0}" "${net_in}" "${net_out}")"

    curl -sS -o /dev/null --max-time 10 \
      --request POST \
      --header "Authorization: Bearer ${token}" \
      --header "Content-Type: application/json" \
      --data "${payload}" \
      "${metrics_url}" || true

    sleep "${interval}"
  done
}

# Sourced by metrics-sampler_test.sh to exercise the samplers directly.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
