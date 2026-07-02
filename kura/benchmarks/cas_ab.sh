#!/usr/bin/env bash
#
# CAS A/B benchmark: Kura (bare-metal, local-NVMe CAS) vs the legacy Kamal cache
# (S3 write-through), over the real customer HTTP plane.
#
# It exercises the shared `/api/cache/cas/{id}` contract both backends implement:
# POST stores an object under an opaque id (no server-side hash check), GET reads
# it back. Fresh random bytes per PUT avoid dedup, so PUTs measure real writes.
#
# Auth + endpoints come from `tuist cache config`: without the kura client flag it
# resolves the legacy endpoint, with `TUIST_FEATURE_FLAG_kura=1` the account's Kura
# endpoint. The bearer token, account and project handles are parsed from the same
# output, so nothing is hardcoded.
#
# This writes junk blobs into the configured account's PRODUCTION cache on both
# backends (content-addressed, modest volume, reclaimed by normal retention). It
# is a manual, operator-run benchmark — not part of the automated suite.
#
# Tunables (env):
#   SIZES_MB    throughput blob sizes, space separated, each <= 24 (CAS cap 25MB)   [1 8 24]
#   ITERS       iterations per size for the medians                                 [6]
#   PARALLEL    concurrent streams for the aggregate-throughput probe               [16]
#   LATENCY_KB  object size for the small-object latency sweep                       [256]
set -uo pipefail

SIZES_MB=${SIZES_MB:-"1 8 24"}
ITERS=${ITERS:-6}
PARALLEL=${PARALLEL:-16}
LATENCY_KB=${LATENCY_KB:-256}

# --- resolve endpoints + auth from the CLI (never print the token) ---------------
cfg_legacy=$(tuist cache config 2>/dev/null)
cfg_kura=$(TUIST_FEATURE_FLAG_kura=1 tuist cache config 2>/dev/null)
field() { awk -v k="$1:" '$1==k{print $2; exit}'; }

TOKEN=$(printf '%s\n' "$cfg_legacy" | field Token)
ACC=$(printf '%s\n' "$cfg_legacy" | field Account)
PROJ=$(printf '%s\n' "$cfg_legacy" | field Project)
URL_LEGACY=$(printf '%s\n' "$cfg_legacy" | field URL)
URL_KURA=$(printf '%s\n' "$cfg_kura" | field URL)

if [ -z "$TOKEN" ] || [ -z "$URL_LEGACY" ] || [ -z "$URL_KURA" ]; then
  echo "failed to resolve cache config (token/urls). Is the runner authenticated to Tuist?" >&2
  printf 'legacy_url=%q kura_url=%q token_len=%s\n' "$URL_LEGACY" "$URL_KURA" "${#TOKEN}" >&2
  exit 1
fi
# Mask the token in CI logs.
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$TOKEN"

if [ "$URL_KURA" = "$URL_LEGACY" ]; then
  echo "kura and legacy resolved to the same URL ($URL_KURA); account may lack a Kura endpoint or the kura_cache flag. Aborting." >&2
  exit 1
fi

Q="account_handle=${ACC}&project_handle=${PROJ}"
AUTH=(-H "Authorization: Bearer $TOKEN")
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "Kura:   $URL_KURA"
echo "Legacy: $URL_LEGACY"
echo "Account/Project: ${ACC}/${PROJ}   sizes=[$SIZES_MB]MB iters=$ITERS parallel=$PARALLEL latency=${LATENCY_KB}KB"
echo

# --- helpers ---------------------------------------------------------------------
med()  { sort -n | awk '{a[NR]=$1} END{if(NR==0){print 0;exit} print (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}'; }
pctl() { sort -n | awk -v p="$1" '{a[NR]=$1} END{if(NR==0){print 0;exit} i=int(p/100*NR); if(i<1)i=1; print a[i]}'; }
base_for() { [ "$1" = kura ] && echo "$URL_KURA" || echo "$URL_LEGACY"; }
cas_put() { curl -sS -o /dev/null "${AUTH[@]}" -H "Content-Type: application/octet-stream" -X POST --data-binary @"$2" -w '%{http_code} %{speed_upload}' "$1/api/cache/cas/$3?$Q"; }
cas_get() { curl -sS -o /dev/null "${AUTH[@]}" -w '%{http_code} %{speed_download}' "$1/api/cache/cas/$2?$Q"; }

# warm DNS/TLS
for n in kura legacy; do curl -s -o /dev/null "$(base_for "$n")/up" || true; done

SUMMARY=$(mktemp)
emit() { echo "$1"; echo "$1" >> "$SUMMARY"; }

emit "## Kura vs legacy cache — CAS A/B (in-network runner)"
emit ""
emit "Backends: Kura \`$URL_KURA\` vs legacy \`$URL_LEGACY\`, account \`${ACC}/${PROJ}\`."
emit ""

# --- 1) small-object hit latency -------------------------------------------------
emit "### Hit latency (${LATENCY_KB}KB object, ms)"
emit ""
emit "| backend | mode | p50 | p90 | p99 |"
emit "|---|---|---:|---:|---:|"
head -c $((LATENCY_KB*1024)) /dev/urandom > "$TMP/small"
for name in kura legacy; do
  base=$(base_for "$name")
  id="lat-$name-$RANDOM-$(date +%s%N)"
  cas_put "$base" "$TMP/small" "$id" >/dev/null
  # warm: one curl, many requests on a reused connection (per-URL -o so bodies don't leak into -w)
  args=(); for _ in $(seq 1 60); do args+=(-o /dev/null "$base/api/cache/cas/$id?$Q"); done
  curl -sS "${AUTH[@]}" -w '%{time_starttransfer}\n' "${args[@]}" > "$TMP/warm_$name" 2>/dev/null
  w=$(tail -n +2 "$TMP/warm_$name")   # drop 1st (TLS setup) sample
  wp50=$(printf '%s\n' "$w" | med); wp90=$(printf '%s\n' "$w" | pctl 90); wp99=$(printf '%s\n' "$w" | pctl 99)
  # cold: fresh TLS connection each request
  : > "$TMP/cold_$name"
  for _ in $(seq 1 20); do curl -sS -o /dev/null "${AUTH[@]}" -w '%{time_starttransfer}\n' "$base/api/cache/cas/$id?$Q" >> "$TMP/cold_$name"; done
  cp50=$(med < "$TMP/cold_$name"); cp90=$(pctl 90 < "$TMP/cold_$name"); cp99=$(pctl 99 < "$TMP/cold_$name")
  emit "$(awk -v b="$name" -v a="$wp50" -v c="$wp90" -v d="$wp99" 'BEGIN{printf "| %s | warm | %.0f | %.0f | %.0f |", b, a*1000, c*1000, d*1000}')"
  emit "$(awk -v b="$name" -v a="$cp50" -v c="$cp90" -v d="$cp99" 'BEGIN{printf "| %s | cold | %.0f | %.0f | %.0f |", b, a*1000, c*1000, d*1000}')"
done
emit ""

# --- 2) single-stream throughput -------------------------------------------------
emit "### Single-stream throughput (median MB/s, n=$ITERS)"
emit ""
emit "| size | Kura up | Legacy up | Kura down | Legacy down |"
emit "|---|---:|---:|---:|---:|"
for size in $SIZES_MB; do
  bytes=$((size*1024*1024))
  declare -A U D
  for name in kura legacy; do
    base=$(base_for "$name"); ups=""; downs=""
    for i in $(seq 1 "$ITERS"); do
      head -c "$bytes" /dev/urandom > "$TMP/blob"
      id="tp-${size}m-${name}-${i}-${RANDOM}-$(date +%s%N)"
      read pc pu < <(cas_put "$base" "$TMP/blob" "$id"); [ "$pc" = 204 ] && ups+="$pu"$'\n'
      read gc gd < <(cas_get "$base" "$id");            [ "$gc" = 200 ] && downs+="$gd"$'\n'
    done
    U[$name]=$(printf '%s' "$ups" | med); D[$name]=$(printf '%s' "$downs" | med)
  done
  emit "$(awk -v s="$size" -v ku="${U[kura]}" -v lu="${U[legacy]}" -v kd="${D[kura]}" -v ld="${D[legacy]}" \
    'BEGIN{m=1048576; printf "| %sMB | %.1f | %.1f | %.1f | %.1f |", s, ku/m, lu/m, kd/m, ld/m}')"
done
emit ""

# --- 3) parallel aggregate throughput -------------------------------------------
emit "### Aggregate throughput, ${PARALLEL} parallel streams of 8MB (MB/s)"
emit ""
emit "| backend | upload | download |"
emit "|---|---:|---:|"
for name in kura legacy; do
  base=$(base_for "$name")
  head -c $((8*1024*1024)) /dev/urandom > "$TMP/p8"
  # parallel upload of PARALLEL distinct ids
  ids=(); for k in $(seq 1 "$PARALLEL"); do ids+=("par-$name-$k-$RANDOM-$(date +%s%N)"); done
  s=$(date +%s.%N)
  for id in "${ids[@]}"; do cas_put "$base" "$TMP/p8" "$id" >/dev/null & done; wait
  e=$(date +%s.%N)
  up=$(awk -v s="$s" -v e="$e" -v p="$PARALLEL" 'BEGIN{printf "%.1f", (p*8)/(e-s)}')
  # parallel download of those ids
  s=$(date +%s.%N)
  for id in "${ids[@]}"; do cas_get "$base" "$id" >/dev/null & done; wait
  e=$(date +%s.%N)
  dn=$(awk -v s="$s" -v e="$e" -v p="$PARALLEL" 'BEGIN{printf "%.1f", (p*8)/(e-s)}')
  emit "| $name | $up | $dn |"
done
emit ""

# --- publish to the CI job summary ----------------------------------------------
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then cat "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"; fi
rm -f "$SUMMARY"
