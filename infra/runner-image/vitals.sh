#!/bin/bash
# Periodic resource-vitals probe for the macOS Tart runner.
#
# A runner that dies mid-job ("self-hosted runner lost communication
# with the server") leaves no trace of the in-VM memory/CPU pressure
# that likely caused it. On Linux the probe writes to stdout and the
# cluster's log collector ships it to Loki, but a Tart VM's logs die
# with the VM (tart-kubelet doesn't ship them), so there is no log
# path off the box. This probe instead POSTs samples over the network
# to the Tuist server's vitals endpoint, reusing the same SA token and
# URL host the dispatch loop already uses; the server logs each sample
# so it lands in Loki, durable past the VM.
#
# dispatch-poll.sh backgrounds this just before running the GitHub
# Actions runner, so it samples for the job's lifetime and stops when
# the VM halts. Fail-open by design: any missing tool, unreadable
# token, or failed POST is swallowed so it can never block or fail the
# runner. Values are sanitized to digits/dots before they leave the
# box, so a sample can't inject anything into the server's logs.
set -u

# Clamp the interval to a positive integer (default 5s). macOS sampling
# (vm_stat + sysctl) is a touch heavier than reading /proc, so the
# default is slightly slower than the Linux probe's 3s.
interval="${TUIST_RUNNER_VITALS_INTERVAL:-5}"
if ! [ "${interval}" -ge 1 ] 2>/dev/null; then
  interval=5
fi

DISPATCH_URL="${TUIST_RUNNER_DISPATCH_URL:-}"
# Without the dispatch URL there's nothing to derive the vitals
# endpoint from. Exit quietly (fail-open) rather than spin.
[ -n "${DISPATCH_URL}" ] || exit 0
# .../runners/dispatch -> .../runners/vitals
VITALS_URL="${DISPATCH_URL%dispatch}vitals"
SA_TOKEN_PATH="${TUIST_RUNNER_SA_TOKEN_PATH:-/etc/tuist-sa-token}"

# Keep only digits and dots: JSON-safe and injection-safe.
num() { tr -cd '0-9.'; }

# Pull the trailing count out of a `vm_stat` line matched by $1.
pages() { printf '%s\n' "${vmstat}" | awk -v re="$1" '$0 ~ re {v=$NF; gsub(/[^0-9]/,"",v); print v; exit}'; }

while :; do
  if [ -r "${SA_TOKEN_PATH}" ]; then
    token="$(cat "${SA_TOKEN_PATH}")"

    vmstat="$(vm_stat 2>/dev/null || true)"
    page="$(printf '%s\n' "${vmstat}" | awk '/page size of/{print $8; exit}')"
    [ -n "${page}" ] || page=16384
    free="$(pages 'Pages free')"
    inactive="$(pages 'Pages inactive')"
    spec="$(pages 'Pages speculative')"
    comp="$(pages 'occupied by compressor')"
    total_bytes="$(sysctl -n hw.memsize 2>/dev/null)"

    total_mb="$(awk -v b="${total_bytes:-0}" 'BEGIN{printf "%d", b/1048576}')"
    free_mb="$(awk -v p="${page}" -v f="${free:-0}" -v i="${inactive:-0}" -v s="${spec:-0}" 'BEGIN{printf "%d",(f+i+s)*p/1048576}')"
    comp_mb="$(awk -v p="${page}" -v c="${comp:-0}" 'BEGIN{printf "%d", c*p/1048576}')"
    used_mb="$(awk -v t="${total_mb}" -v fr="${free_mb}" 'BEGIN{printf "%d", (t-fr<0)?0:t-fr}')"
    free_pct="$(awk -v fr="${free_mb}" -v t="${total_mb}" 'BEGIN{printf "%d", (t>0)? fr*100/t : 0}')"

    loads="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')"
    l1="$(printf '%s' "${loads}" | awk '{print $1}' | num)"
    l5="$(printf '%s' "${loads}" | awk '{print $2}' | num)"
    l15="$(printf '%s' "${loads}" | awk '{print $3}' | num)"

    swap_used="$(sysctl -n vm.swapusage 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="used"){print $(i+2); exit}}' | num)"

    payload="$(printf '{"mem_total_mb":"%s","mem_free_mb":"%s","mem_used_mb":"%s","mem_free_pct":"%s","compressed_mb":"%s","swap_used_mb":"%s","load1":"%s","load5":"%s","load15":"%s"}' \
      "${total_mb}" "${free_mb}" "${used_mb}" "${free_pct}" "${comp_mb}" "${swap_used:-0}" "${l1:-0}" "${l5:-0}" "${l15:-0}")"

    curl -sS -m 5 -X POST \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      --data "${payload}" \
      "${VITALS_URL}" >/dev/null 2>&1 || true
  fi
  sleep "${interval}"
done
