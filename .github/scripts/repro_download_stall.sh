#!/usr/bin/env bash
#
# repro_download_stall.sh
#
# Reproduce / diagnose the SwiftPM binary-artifact download stall from
# runner-job-89247178602 (tuist install hung ~6h on binary artifact downloads).
#
# Streams each of the 10 artifact URLs to /dev/null with a stall watchdog and
# reports transport-level facts: negotiated HTTP version, CDN edge IP, connect
# time, time-to-first-byte, total time, bytes moved, avg speed, and a stall
# classification. Bodies are discarded; only small logs land under OUT_DIR.
#
# Run this INSIDE a runner VM (a Tuist macOS runner, or a GitHub-hosted runner)
# so it exercises the same egress path. The MODES discriminate the hypotheses:
#
#   seq-h2  vs  seq-h1   HTTP/2 vs forced HTTP/1.1, one URL at a time.
#                        If h2 stalls and h1 is clean -> HTTP/2-level problem.
#   conc                 10 independent curl processes at once (separate
#                        connections). Stress on NAT / egress conntrack.
#   pool                 one `curl --parallel` over all 10 (shared connection
#                        pool, same-host HTTP/2 coalescing) -- closest to what
#                        URLSession/SwiftPM actually does. If `pool` stalls but
#                        `conc` is clean -> HTTP/2 head-of-line blocking on the
#                        coalesced connection (6 URLs share releases.amplify.aws).
#
# Exit-code driven stall detection via curl --speed-limit/--speed-time:
#   OK              transfer completed
#   STALL-MIDXFER   bytes flowed, then throughput fell to ~0 (the smoking gun)
#   STALL-TTFB      connected/TLS ok, first byte never arrived
#   CONNECT-TIMEOUT never established a connection
#   DNS-FAIL / TLS-FAIL / ERR(n)  other transport failures
#
# Tunables (env overridable):
#   MAX_TIME=300        hard per-download ceiling (s)
#   CONNECT_TIMEOUT=20  connect ceiling (s)
#   STALL_BYTES=1024    abort if avg speed < this ...
#   STALL_SECS=30       ... sustained for this long (the stall watchdog)
#   MODES="seq-h2 seq-h1 conc pool"
#   LIMIT_URLS=0        0=all, N=first N URLs (quick smoke tests)
#   OUT_DIR=./download-stall-repro-<timestamp>

set -u

MAX_TIME="${MAX_TIME:-300}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-20}"
STALL_BYTES="${STALL_BYTES:-1024}"
STALL_SECS="${STALL_SECS:-30}"
MODES="${MODES:-seq-h2 seq-h1 conc pool}"
LIMIT_URLS="${LIMIT_URLS:-0}"
OUT_DIR="${OUT_DIR:-./download-stall-repro-$(date +%Y%m%d-%H%M%S)}"

URLS=(
  "https://releases.amplify.aws/aws-sdk-ios/AWSCognitoIdentityProviderASF-2.41.0.zip"
  "https://releases.amplify.aws/aws-sdk-ios/AWSIoT-2.41.0.zip"
  "https://releases.amplify.aws/aws-sdk-ios/AWSCore-2.41.0.zip"
  "https://releases.amplify.aws/aws-sdk-ios/AWSCognitoIdentityProvider-2.41.0.zip"
  "https://releases.amplify.aws/aws-sdk-ios/AWSMobileClientXCF-2.41.0.zip"
  "https://dl.cloudsmith.io/QQ43WPa2Y7VlFUM3/proglove/markconnectiossdk-prod/raw/names/ConnectSDK-2.9.0.xcframework/versions/2.9.0/ConnectSDK-2.9.0.xcframework.zip?accept_eula=8"
  "https://releases.amplify.aws/aws-sdk-ios/AWSAuthCore-2.41.0.zip"
  "https://github.com/luciqai/luciq-ios-sdk/releases/download/19.8.1/Luciq-XCFramework.zip"
  "https://software.mobile.pendo.io/artifactory/ios-sdk-release/3.13.1.11743/pendo-ios-sdk-xcframework.3.13.1.11743.zip"
  "https://github.com/AzureAD/microsoft-authentication-library-for-objc/releases/download/2.13.0/MSAL.zip"
)

# Delimited curl -w record. url_effective last (post-redirect identity in pool mode).
WRITE_FMT='%{http_code}|%{http_version}|%{num_redirects}|%{remote_ip}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}|%{size_download}|%{speed_download}|%{url_effective}'

mkdir -p "$OUT_DIR"

have_h2=1
curl -V 2>/dev/null | grep -qi 'HTTP2' || have_h2=0
have_parallel=1
curl --help all 2>/dev/null | grep -q -- '--parallel' || have_parallel=0

label_for() {  # basename before '?', stripped of extension noise
  local u="$1" b
  b="${u%%\?*}"; b="${b##*/}"
  printf '%s' "$b"
}

host_for() { local u="$1"; u="${u#*://}"; printf '%s' "${u%%/*}"; }

fmt_mb()  { awk "BEGIN{printf \"%.1f\", ${1:-0}/1048576}"; }
fmt_mbs() { awk "BEGIN{printf \"%.2f\", ${1:-0}/1048576}"; }

classify() {  # $1=rc  $2=record  -> sets global VERDICT
  local rc="$1" rec="$2"
  local code ver redir ip t_dns t_conn t_tls t_ttfb t_total size speed urleff
  IFS='|' read -r code ver redir ip t_dns t_conn t_tls t_ttfb t_total size speed urleff <<<"$rec"
  case "$rc" in
    0)  VERDICT="OK" ;;
    28)
      if   awk "BEGIN{exit !(${t_conn:-0}==0)}"; then VERDICT="CONNECT-TIMEOUT"
      elif awk "BEGIN{exit !(${size:-0}>0)}";    then VERDICT="STALL-MIDXFER"
      elif awk "BEGIN{exit !(${t_ttfb:-0}==0)}"; then VERDICT="STALL-TTFB"
      else VERDICT="STALL"; fi ;;
    6)  VERDICT="DNS-FAIL" ;;
    7)  VERDICT="CONNECT-REFUSED" ;;
    35|60|58|59) VERDICT="TLS-FAIL" ;;
    *)  VERDICT="ERR($rc)" ;;
  esac
}

print_header() {
  printf '%-38s %-5s %-4s %-15s %8s %8s %8s %9s %9s  %s\n' \
    LABEL PROTO HTTP REMOTE_IP CONN_s TTFB_s TOTAL_s SIZE_MB MB/s VERDICT
  printf '%s\n' "----------------------------------------------------------------------------------------------------------------------------"
}

print_row() {  # $1=label $2=proto $3=rc $4=record
  local label="$1" proto="$2" rc="$3" rec="$4"
  local code ver redir ip t_dns t_conn t_tls t_ttfb t_total size speed urleff
  IFS='|' read -r code ver redir ip t_dns t_conn t_tls t_ttfb t_total size speed urleff <<<"$rec"
  classify "$rc" "$rec"
  printf '%-38s %-5s %-4s %-15s %8s %8s %8s %9s %9s  %s\n' \
    "${label:0:38}" "$proto" "${ver:-?}" "${ip:-?}" \
    "${t_conn:-?}" "${t_ttfb:-?}" "${t_total:-?}" "$(fmt_mb "$size")" "$(fmt_mbs "$speed")" "$VERDICT"
  printf '%s\t%s\t%s\t%s\n' "$label" "$proto" "$VERDICT" "$rec" >>"$OUT_DIR/results.tsv"
}

probe() {  # $1=label $2=proto(h1|h2) $3=url  -> prints record to stdout, rc via return
  local label="$1" proto="$2" url="$3"
  local pf=()
  case "$proto" in h1) pf=(--http1.1);; h2) pf=(--http2);; esac
  local trace="$OUT_DIR/trace-${label}-${proto}.log"
  local rec
  rec=$(curl -sS -L --max-redirs 5 "${pf[@]}" \
          --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
          --speed-limit "$STALL_BYTES" --speed-time "$STALL_SECS" \
          -o /dev/null -w "$WRITE_FMT" -v \
          "$url" 2>>"$trace")
  local rc=$?
  printf '%s' "$rec"
  return $rc
}

selected_urls() {
  local n="${#URLS[@]}"
  if [ "$LIMIT_URLS" -gt 0 ] && [ "$LIMIT_URLS" -lt "$n" ]; then n="$LIMIT_URLS"; fi
  local i=0
  while [ "$i" -lt "$n" ]; do printf '%s\n' "${URLS[$i]}"; i=$((i+1)); done
}

run_sequential() {  # $1=proto
  local proto="$1" url label rec rc
  echo; echo "### MODE seq-${proto}  (one URL at a time, $( [ "$proto" = h2 ] && echo HTTP/2 || echo HTTP/1.1 ))"
  print_header
  while IFS= read -r url; do
    label="$(label_for "$url")"
    rec="$(probe "$label" "$proto" "$url")"; rc=$?
    print_row "$label" "$proto" "$rc" "$rec"
  done < <(selected_urls)
}

run_concurrent() {  # independent processes, HTTP/2
  [ "$have_h2" = 1 ] || { echo "(skipping conc: curl has no HTTP/2)"; return; }
  echo; echo "### MODE conc  (all URLs at once, independent connections, HTTP/2)"
  local url label pids=() started=$(date +%s)
  : >"$OUT_DIR/.conc"
  while IFS= read -r url; do
    label="$(label_for "$url")"
    { rec="$(probe "$label" h2 "$url")"; rc=$?; printf '%s\t%s\t%s\n' "$label" "$rc" "$rec" >>"$OUT_DIR/.conc"; } &
    pids+=($!)
  done < <(selected_urls)
  for p in "${pids[@]}"; do wait "$p"; done
  echo "(wall: $(( $(date +%s) - started ))s)"
  print_header
  while IFS=$'\t' read -r label rc rec; do print_row "$label" h2 "$rc" "$rec"; done <"$OUT_DIR/.conc"
  rm -f "$OUT_DIR/.conc"
}

run_pool() {  # single curl --parallel: shared pool + same-host HTTP/2 coalescing
  [ "$have_parallel" = 1 ] || { echo "(skipping pool: curl lacks --parallel)"; return; }
  [ "$have_h2" = 1 ]       || { echo "(skipping pool: curl has no HTTP/2)"; return; }
  echo; echo "### MODE pool  (curl --parallel, shared connection pool + HTTP/2 coalescing)"
  local args=() url started=$(date +%s)
  while IFS= read -r url; do args+=( -o /dev/null "$url" ); done < <(selected_urls)
  local trace="$OUT_DIR/trace-pool.log"
  print_header
  # -w prints one record per completed transfer (order = completion order).
  curl -sS -L --max-redirs 5 --http2 --parallel --parallel-max 12 \
       --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
       --speed-limit "$STALL_BYTES" --speed-time "$STALL_SECS" \
       -w "$WRITE_FMT\n" -v "${args[@]}" 2>>"$trace" \
  | while IFS= read -r rec; do
      [ -n "$rec" ] || continue
      local urleff label
      urleff="${rec##*|}"; label="$(label_for "$urleff")"
      # Pool mode can't attribute a curl exit code per transfer; infer from record.
      local size ttfb; IFS='|' read -r _ _ _ _ _ _ _ ttfb _ size _ _ <<<"$rec"
      local rc=0
      awk "BEGIN{exit !(${size:-0}==0)}" && rc=28
      print_row "$label" h2 "$rc" "$rec"
    done
  echo "(wall: $(( $(date +%s) - started ))s -- a wall near MAX_TIME with missing rows means transfers wedged)"
}

echo "repro_download_stall.sh"
echo "host: $(hostname 2>/dev/null)   curl: $(curl -V 2>/dev/null | head -1)"
echo "MAX_TIME=${MAX_TIME}s CONNECT_TIMEOUT=${CONNECT_TIMEOUT}s stall=<${STALL_BYTES}B/s for ${STALL_SECS}s  MODES='${MODES}'  URLs=$(selected_urls | wc -l | tr -d ' ')"
echo "logs -> $OUT_DIR"
: >"$OUT_DIR/results.tsv"

for m in $MODES; do
  case "$m" in
    seq-h2) [ "$have_h2" = 1 ] && run_sequential h2 || echo "(skipping seq-h2: no HTTP/2)";;
    seq-h1) run_sequential h1 ;;
    conc)   run_concurrent ;;
    pool)   run_pool ;;
    *) echo "unknown mode: $m" ;;
  esac
done

echo
echo "### SUMMARY"
if [ -s "$OUT_DIR/results.tsv" ]; then
  awk -F'\t' '{c[$3]++} END{for (v in c) printf "  %-16s %d\n", v, c[v]}' "$OUT_DIR/results.tsv" | sort
  if grep -q 'STALL-MIDXFER' "$OUT_DIR/results.tsv"; then
    echo
    echo "  >> MID-TRANSFER STALL reproduced (bytes flowed, then throughput -> 0)."
    echo "     This is the runner-job-89247178602 failure. Offending transfers:"
    awk -F'\t' '$3=="STALL-MIDXFER"{printf "       - %s (%s)\n", $1, $2}' "$OUT_DIR/results.tsv"
  fi
fi
echo "  full per-connection traces: $OUT_DIR/trace-*.log ; records: $OUT_DIR/results.tsv"
