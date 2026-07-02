#!/usr/bin/env bash
#
# Kura CAS benchmark (absolute performance, from an in-network runner), with an
# optional A/B against the legacy Kamal cache.
#
# It exercises the /api/cache/cas/{id} contract: POST stores an object under an
# opaque id (no server-side hash check), GET reads it back. Fresh random bytes per
# PUT avoid dedup, so PUTs measure real writes.
#
# The auth token + Kura endpoint come from `tuist cache config` (the account is
# routed to Kura server-side). The same account-scoped token also authorizes the
# legacy backend, so if BENCH_LEGACY_URL is set the script benchmarks it too for a
# side-by-side — otherwise it reports Kura alone. Primary question: is Kura as fast
# as we expect from inside our network (saturates the pipe, low hit latency)?
#
# This writes junk blobs into the account's PRODUCTION cache (content-addressed,
# modest volume, reclaimed by normal retention). Operator-run benchmark, not part
# of the automated suite.
#
# Tunables (env):
#   SIZES_MB         throughput blob sizes, space separated, each <= 24            [1 8 24]
#   ITERS            iterations per size for the medians                           [6]
#   PARALLEL         concurrent streams for the aggregate-throughput probe         [16]
#   LATENCY_KB       object size for the latency sweep                             [256]
#   BENCH_LEGACY_URL legacy cache base URL to A/B against ("" to skip)             [https://cache-eu-central.tuist.dev]
#   FULL_HANDLE      account/project the cache token is minted for                 [tuist/tuist]
set -uo pipefail

SIZES_MB=${SIZES_MB:-"1 8 24"}
ITERS=${ITERS:-6}
PARALLEL=${PARALLEL:-16}
LATENCY_KB=${LATENCY_KB:-256}
LEGACY_URL=${BENCH_LEGACY_URL:-https://cache-eu-central.tuist.dev}
[ "$LEGACY_URL" = none ] && LEGACY_URL=""   # sentinel to benchmark Kura alone

# The tuist-linux runner ships the repo's mise dev environment, which points the CLI
# at a local dev server. Neutralize it so auth + cache config target production.
unset TUIST_SERVER_URL TUIST_URL TUIST_CACHE_SERVER_URL TUIST_CONFIG_URL TUIST_CACHE_CONFIG_SERVER_URL 2>/dev/null || true
FULL_HANDLE=${FULL_HANDLE:-tuist/tuist}
SERVER_URL=${BENCH_SERVER_URL:-https://tuist.dev}

# On CI this authenticates via GitHub OIDC (needs id-token: write).
tuist auth login >/dev/null 2>&1 || true

redact() { sed -E 's/("token"[[:space:]]*:[[:space:]]*")[^"]*/\1<redacted>/'; }
json_field() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"\$/\1/"; }
unesc() { sed 's#\\/#/#g'; }

cfg=$(tuist cache config "$FULL_HANDLE" --url "$SERVER_URL" --json 2>&1) || true
TOKEN=$(printf '%s' "$cfg" | json_field token)
ACC=$(printf '%s' "$cfg" | json_field account_handle)
PROJ=$(printf '%s' "$cfg" | json_field project_handle)
URL_KURA=$(printf '%s' "$cfg" | json_field url | unesc)

if [ -z "$TOKEN" ] || [ -z "$URL_KURA" ]; then
  echo "failed to resolve cache config (token/url). Raw output (token redacted):" >&2
  printf '%s\n' "$cfg" | redact >&2
  exit 1
fi
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$TOKEN"

# Backends: Kura always; legacy only if a distinct URL was provided.
names=(kura); declare -A URLS=([kura]="$URL_KURA")
if [ -n "$LEGACY_URL" ] && [ "$LEGACY_URL" != "$URL_KURA" ]; then
  names+=(legacy); URLS[legacy]="$LEGACY_URL"
fi

Q="account_handle=${ACC}&project_handle=${PROJ}"
AUTH=(-H "Authorization: Bearer $TOKEN")
CT=(--connect-timeout 10 --max-time 180)   # no request may hang the whole job
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

med()  { sort -n | awk '{a[NR]=$1} END{if(NR==0){print 0;exit} print (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}'; }
pctl() { sort -n | awk -v p="$1" '{a[NR]=$1} END{if(NR==0){print 0;exit} i=int(p/100*NR); if(i<1)i=1; print a[i]}'; }
cas_put() { curl -sS "${CT[@]}" -o /dev/null "${AUTH[@]}" -H "Content-Type: application/octet-stream" -X POST --data-binary @"$2" -w '%{http_code} %{speed_upload}' "$1/api/cache/cas/$3?$Q"; }
cas_get() { curl -sS "${CT[@]}" -o /dev/null "${AUTH[@]}" -w '%{http_code} %{speed_download}' "$1/api/cache/cas/$2?$Q"; }

# Reachability probe: fail fast + loud if the runner can't reach a backend, rather
# than hanging until the job timeout.
echo "== reachability =="
for n in "${names[@]}"; do
  probe=$(curl -sS --connect-timeout 10 --max-time 20 -o /dev/null -w '%{http_code} %{time_total}s' "${URLS[$n]}/up" 2>&1) \
    && echo "  $n ${URLS[$n]}/up -> $probe" \
    || { echo "  $n ${URLS[$n]}/up -> UNREACHABLE ($probe)"; [ "$n" = kura ] && { echo "Kura endpoint unreachable from this runner; aborting." >&2; exit 1; }; }
done
echo

SUMMARY=$(mktemp)
emit() { echo "$1"; echo "$1" >> "$SUMMARY"; }

emit "## Kura CAS benchmark (public CI runner)"
emit ""
if [ "${#names[@]}" -gt 1 ]; then
  emit "Kura \`$URL_KURA\` vs legacy \`${URLS[legacy]}\`, account \`${ACC}/${PROJ}\`."
else
  emit "Kura \`$URL_KURA\`, account \`${ACC}/${PROJ}\` (legacy A/B skipped)."
fi
emit "Sizes [$SIZES_MB]MB, iters $ITERS, parallel $PARALLEL, latency object ${LATENCY_KB}KB."
emit ""

# --- 1) small-object hit latency -------------------------------------------------
emit "### Hit latency (${LATENCY_KB}KB object, ms)"
emit ""
emit "| backend | mode | p50 | p90 | p99 |"
emit "|---|---|---:|---:|---:|"
head -c $((LATENCY_KB*1024)) /dev/urandom > "$TMP/small"
for name in "${names[@]}"; do
  base="${URLS[$name]}"
  id="lat-$name-$RANDOM-$(date +%s%N)"
  cas_put "$base" "$TMP/small" "$id" >/dev/null
  args=(); for _ in $(seq 1 60); do args+=(-o /dev/null "$base/api/cache/cas/$id?$Q"); done
  curl -sS --connect-timeout 10 --max-time 120 "${AUTH[@]}" -w '%{time_starttransfer}\n' "${args[@]}" > "$TMP/warm_$name" 2>/dev/null
  w=$(tail -n +2 "$TMP/warm_$name")
  wp50=$(printf '%s\n' "$w" | med); wp90=$(printf '%s\n' "$w" | pctl 90); wp99=$(printf '%s\n' "$w" | pctl 99)
  : > "$TMP/cold_$name"
  for _ in $(seq 1 20); do curl -sS --connect-timeout 10 --max-time 20 -o /dev/null "${AUTH[@]}" -w '%{time_starttransfer}\n' "$base/api/cache/cas/$id?$Q" >> "$TMP/cold_$name"; done
  cp50=$(med < "$TMP/cold_$name"); cp90=$(pctl 90 < "$TMP/cold_$name"); cp99=$(pctl 99 < "$TMP/cold_$name")
  emit "$(awk -v b="$name" -v a="$wp50" -v c="$wp90" -v d="$wp99" 'BEGIN{printf "| %s | warm | %.0f | %.0f | %.0f |", b, a*1000, c*1000, d*1000}')"
  emit "$(awk -v b="$name" -v a="$cp50" -v c="$cp90" -v d="$cp99" 'BEGIN{printf "| %s | cold | %.0f | %.0f | %.0f |", b, a*1000, c*1000, d*1000}')"
done
emit ""

# --- 2) single-stream throughput -------------------------------------------------
emit "### Single-stream throughput (median MB/s, n=$ITERS)"
emit ""
emit "| size | backend | upload | download |"
emit "|---|---|---:|---:|"
for size in $SIZES_MB; do
  bytes=$((size*1024*1024))
  for name in "${names[@]}"; do
    base="${URLS[$name]}"; ups=""; downs=""
    for i in $(seq 1 "$ITERS"); do
      head -c "$bytes" /dev/urandom > "$TMP/blob"
      id="tp-${size}m-${name}-${i}-${RANDOM}-$(date +%s%N)"
      read -r pc pu < <(cas_put "$base" "$TMP/blob" "$id"); [ "$pc" = 204 ] && ups+="$pu"$'\n'
      read -r gc gd < <(cas_get "$base" "$id");            [ "$gc" = 200 ] && downs+="$gd"$'\n'
    done
    um=$(printf '%s' "$ups" | med); dm=$(printf '%s' "$downs" | med)
    emit "$(awk -v s="$size" -v b="$name" -v u="$um" -v d="$dm" 'BEGIN{m=1048576; printf "| %sMB | %s | %.1f | %.1f |", s, b, u/m, d/m}')"
  done
done
emit ""

# --- 3) parallel aggregate throughput -------------------------------------------
emit "### Aggregate throughput, ${PARALLEL} parallel streams of 8MB (MB/s)"
emit ""
emit "| backend | upload | download |"
emit "|---|---:|---:|"
head -c $((8*1024*1024)) /dev/urandom > "$TMP/p8"
for name in "${names[@]}"; do
  base="${URLS[$name]}"
  ids=(); for k in $(seq 1 "$PARALLEL"); do ids+=("par-$name-$k-$RANDOM-$(date +%s%N)"); done
  s=$(date +%s.%N); for id in "${ids[@]}"; do cas_put "$base" "$TMP/p8" "$id" >/dev/null & done; wait; e=$(date +%s.%N)
  up=$(awk -v s="$s" -v e="$e" -v p="$PARALLEL" 'BEGIN{printf "%.1f", (p*8)/(e-s)}')
  s=$(date +%s.%N); for id in "${ids[@]}"; do cas_get "$base" "$id" >/dev/null & done; wait; e=$(date +%s.%N)
  dn=$(awk -v s="$s" -v e="$e" -v p="$PARALLEL" 'BEGIN{printf "%.1f", (p*8)/(e-s)}')
  emit "| $name | $up | $dn |"
done
emit ""

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then cat "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"; fi
rm -f "$SUMMARY"
