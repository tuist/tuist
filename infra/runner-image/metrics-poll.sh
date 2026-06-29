#!/bin/bash
# Samples the runner VM's machine metrics (CPU / memory / network /
# disk) every few seconds and POSTs them to the Tuist server so the
# job detail page can chart them. Forked into the background by
# dispatch-poll.sh right before it hands off to the GitHub Actions
# runner, so it samples for the job's full duration; the VM halts when
# the job ends (dispatch-poll's EXIT trap), which stops this loop.
#
# Auth + addressing mirror dispatch-poll.sh: the Pod's own projected SA
# token (/etc/tuist-sa-token, audience tuist-runners-dispatch) is the
# Bearer credential, and the endpoint is the dispatch URL with
# `/dispatch` swapped for `/pods/<pod>/metrics`. The server resolves the
# Pod to its job; an unclaimed Pod is a no-op there. Fail-open: a bad
# sample or a failed POST is logged and skipped, never blocking the job.
#
# macOS is sampled whole-VM (one Pod == one VM): there are no cgroups,
# so CPU/memory/disk describe the guest and network sums the VM's
# interfaces. `cpu_iowait_percent` has no macOS source and is omitted
# (the server defaults it to 0).

set -uo pipefail

LOG=/var/log/tuist-runner/metrics.log
mkdir -p /var/log/tuist-runner 2>/dev/null || true
exec >>"${LOG}" 2>&1

if [ -f /etc/tuist.env ]; then
  # shellcheck disable=SC1091
  source /etc/tuist.env
fi

interval="${TUIST_RUNNER_METRICS_INTERVAL:-15}"

if [ -z "${TUIST_RUNNER_DISPATCH_URL:-}" ] || [ -z "${TUIST_RUNNER_POD_NAME:-}" ]; then
  echo "$(date -u +%FT%TZ) metrics-poll: dispatch URL or pod name unset; not sampling"
  exit 0
fi

SA_TOKEN="$(cat /etc/tuist-sa-token 2>/dev/null || true)"
if [ -z "${SA_TOKEN}" ]; then
  echo "$(date -u +%FT%TZ) metrics-poll: SA token unreadable; not sampling"
  exit 0
fi

metrics_url="${TUIST_RUNNER_DISPATCH_URL%/dispatch}/pods/${TUIST_RUNNER_POD_NAME}/metrics"
pagesize="$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)"
mem_total="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"

echo "$(date -u +%FT%TZ) metrics-poll: sampling every ${interval}s -> ${metrics_url}"

prev_rx=""
prev_tx=""

# cpu_busy_percent reads top's second sample (an interval average; the
# first sample is since-boot) and derives busy = 100 - idle.
cpu_busy_percent() {
  local line idle
  line="$(top -l 2 -n 0 2>/dev/null | awk '/CPU usage/ {l=$0} END {print l}')"
  idle="$(printf '%s' "${line}" | sed -n 's/.*, \([0-9.]*\)% idle.*/\1/p')"
  awk -v i="${idle:-100}" 'BEGIN { v = 100 - i; if (v < 0) v = 0; if (v > 100) v = 100; printf "%.1f", v }'
}

# mem_used_bytes counts active + wired + compressed pages as "used".
mem_used_bytes() {
  vm_stat 2>/dev/null | awk -v ps="${pagesize}" '
    /Pages active/                 { gsub(/\./, "", $3); active = $3 }
    /Pages wired down/             { gsub(/\./, "", $4); wired = $4 }
    /Pages occupied by compressor/ { gsub(/\./, "", $5); comp = $5 }
    END { printf "%d", (active + wired + comp) * ps }'
}

# net_totals echoes cumulative "rx tx" bytes summed over the VM's
# non-loopback interfaces (the Link rows carry the byte counters).
net_totals() {
  netstat -ibn 2>/dev/null | awk '
    $3 ~ /^<Link/ && $1 != "lo0" { rx += $7; tx += $10 }
    END { printf "%d %d", rx + 0, tx + 0 }'
}

# disk_totals echoes "used total" bytes for the volume the job writes
# to. On APFS `/` is the sealed, read-only system volume (a few GB);
# the runner's work lands on the firmlinked Data volume, so sample that.
disk_totals() {
  df -k /System/Volumes/Data 2>/dev/null | awk 'NR == 2 { printf "%d %d", $3 * 1024, $2 * 1024 }'
}

delta() {
  # delta cur prev -> max(0, cur-prev); a counter reset reports 0.
  awk -v c="$1" -v p="$2" 'BEGIN { d = c - p; if (d < 0) d = 0; printf "%d", d }'
}

while true; do
  ts="$(date +%s)"
  cpu="$(cpu_busy_percent)"
  mem_used="$(mem_used_bytes)"
  read -r rx tx <<<"$(net_totals)"
  read -r disk_used disk_total <<<"$(disk_totals)"

  if [ -n "${prev_rx}" ]; then
    net_in="$(delta "${rx:-0}" "${prev_rx}")"
    net_out="$(delta "${tx:-0}" "${prev_tx}")"
  else
    net_in=0
    net_out=0
  fi
  prev_rx="${rx:-0}"
  prev_tx="${tx:-0}"

  payload="$(printf '{"samples":[{"timestamp":%s,"cpu_usage_percent":%s,"memory_used_bytes":%s,"memory_total_bytes":%s,"network_bytes_in":%s,"network_bytes_out":%s,"disk_used_bytes":%s,"disk_total_bytes":%s}]}' \
    "${ts}" "${cpu:-0}" "${mem_used:-0}" "${mem_total:-0}" "${net_in}" "${net_out}" "${disk_used:-0}" "${disk_total:-0}")"

  curl -sS -o /dev/null --max-time 10 \
    --request POST \
    --header "Authorization: Bearer ${SA_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "${payload}" \
    "${metrics_url}" || true

  sleep "${interval}"
done
