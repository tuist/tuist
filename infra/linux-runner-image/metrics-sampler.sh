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

set -uo pipefail

TOKEN_PATH="${TUIST_RUNNER_TOKEN_PATH:-/var/run/secrets/tuist-runner/token}"
DISK_PATH="${TUIST_RUNNER_DISK_PATH:-/var/lib/tuist-runner}"
interval="${TUIST_RUNNER_METRICS_INTERVAL:-15}"

log() { echo "$(date -u +%FT%TZ) metrics-sampler: $*"; }

if [ -z "${TUIST_RUNNER_DISPATCH_URL:-}" ] || [ -z "${TUIST_RUNNER_POD_NAME:-}" ]; then
  log "dispatch URL or pod name unset; not sampling"
  exit 0
fi

metrics_url="${TUIST_RUNNER_DISPATCH_URL%/dispatch}/pods/${TUIST_RUNNER_POD_NAME}/metrics"
mem_total_bytes=$(awk '/^MemTotal:/ { print $2 * 1024 }' /proc/meminfo 2>/dev/null || echo 0)

# The sidecar starts at Pod boot, but a warm-standby Pod has no job
# yet — sampling then would just no-op against the server and add load
# for every idle Pod. The poller stages the JIT here the instant a job
# is claimed, so wait for it: sampling then spans exactly the job, the
# same window the macOS sampler covers.
jit_path="${TUIST_RUNNER_JIT_PATH:-/var/lib/tuist-runner/jit}"
log "waiting for a claimed job (JIT at ${jit_path}) before sampling"
while [ ! -f "${jit_path}" ]; do sleep 1; done

log "job claimed; sampling every ${interval}s -> ${metrics_url}"

# read_cpu echoes "total idle_all iowait" jiffies from /proc/stat's
# aggregate cpu line (idle_all = idle + iowait).
read_cpu() {
  awk '/^cpu / { total = 0; for (i = 2; i <= NF; i++) total += $i; print total, $5 + $6, $6; exit }' /proc/stat
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
    END { printf "%d %d", rx + 0, tx + 0 }' /proc/net/dev 2>/dev/null
}

# delta cur prev -> max(0, cur-prev); a counter reset reports 0.
delta() {
  awk -v c="$1" -v p="$2" 'BEGIN { d = c - p; if (d < 0) d = 0; printf "%d", d }'
}

prev_rx=""
prev_tx=""

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

  mem_avail_bytes=$(awk '/^MemAvailable:/ { print $2 * 1024 }' /proc/meminfo 2>/dev/null || echo 0)
  mem_used=$(awk -v t="${mem_total_bytes:-0}" -v a="${mem_avail_bytes:-0}" 'BEGIN { u = t - a; if (u < 0) u = 0; printf "%d", u }')

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

  read -r disk_used disk_total <<<"$(df -k "${DISK_PATH}" 2>/dev/null | awk 'NR == 2 { printf "%d %d", $3 * 1024, $2 * 1024 }')"

  token="$(cat "${TOKEN_PATH}" 2>/dev/null || true)"
  if [ -z "${token}" ]; then
    log "SA token unreadable at ${TOKEN_PATH}; skipping POST"
    sleep "${interval}"
    continue
  fi

  payload="$(printf '{"samples":[{"timestamp":%s,"cpu_usage_percent":%s,"cpu_iowait_percent":%s,"memory_used_bytes":%s,"memory_total_bytes":%s,"network_bytes_in":%s,"network_bytes_out":%s,"disk_used_bytes":%s,"disk_total_bytes":%s}]}' \
    "${ts}" "${cpu:-0}" "${iowait:-0}" "${mem_used:-0}" "${mem_total_bytes:-0}" "${net_in}" "${net_out}" "${disk_used:-0}" "${disk_total:-0}")"

  curl -sS -o /dev/null --max-time 10 \
    --request POST \
    --header "Authorization: Bearer ${token}" \
    --header "Content-Type: application/json" \
    --data "${payload}" \
    "${metrics_url}" || true

  sleep "${interval}"
done
