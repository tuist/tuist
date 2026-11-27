#!/bin/bash
# Experiment: boots each named simulator once, waits until the guest is quiet,
# and shuts it down, then asserts nothing is left booted. Lines start with
# SIMWARM. With WARM_PARALLEL=1 all devices boot and settle together.
# Usage: warm.sh '<runtime id>|<device name>'...
set -euo pipefail
JQ=/opt/homebrew/bin/jq
DEVICES="$HOME/Library/Developer/CoreSimulator/Devices"
now() { perl -MTime::HiRes=time -e 'printf "%.1f", time'; }
# Only processes running inside a simulator runtime, so host noise does not count.
cpu() { ps -A -o %cpu=,comm= | awk '/CoreSimulator/ {s+=$1} END {printf "%d", s}'; }
since() { perl -e "printf '%.1f', $2 - $1"; }

# Waits until simulator CPU stays under 60% per booted device for 15 s.
settle() {
  local quiet=0 i=0
  while [ "$quiet" -lt 3 ] && [ "$i" -lt 120 ]; do
    sleep 5; i=$((i + 1))
    if [ "$(cpu)" -lt $((60 * $1)) ]; then quiet=$((quiet + 1)); else quiet=0; fi
  done
}

echo "SIMWARM serial $(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}') user $(id -un) cpus $(sysctl -n hw.ncpu) parallel ${WARM_PARALLEL:-0}"
udids=()
for spec in "$@"; do
  rt=${spec%%|*}
  name=${spec#*|}
  udid=$(xcrun simctl list devices -j | $JQ -r --arg rt "$rt" --arg n "$name" '.devices[$rt][]? | select(.name == $n) | .udid' | head -n1)
  [ -n "$udid" ] || { echo "SIMWARM missing: $name on $rt" >&2; exit 1; }
  udids+=("$udid")
done

t0=$(now)
if [ "${WARM_PARALLEL:-0}" = 1 ]; then
  pids=()
  for u in "${udids[@]}"; do
    ( xcrun simctl bootstatus "$u" -b >/dev/null; echo "SIMWARM booted $u after $(since "$t0" "$(now)")s" ) &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  b=$(now)
  settle "${#udids[@]}"
  q=$(now)
  xcrun simctl shutdown all
  e=$(now)
  echo "SIMWARM warmed ${#udids[@]} in parallel: boot $(since "$t0" "$b")s settle $(since "$b" "$q")s shutdown $(since "$q" "$e")s"
  for u in "${udids[@]}"; do echo "SIMWARM data $u $(du -sh "$DEVICES/$u/data" | cut -f1)"; done
else
  for i in "${!udids[@]}"; do
    u=${udids[$i]}
    s=$(now)
    xcrun simctl bootstatus "$u" -b >/dev/null
    b=$(now)
    settle 1
    q=$(now)
    xcrun simctl shutdown "$u"
    e=$(now)
    echo "SIMWARM warmed ${*:$((i + 1)):1} ($u): boot $(since "$s" "$b")s settle $(since "$b" "$q")s shutdown $(since "$q" "$e")s data $(du -sh "$DEVICES/$u/data" 2>/dev/null | cut -f1)"
  done
fi
echo "SIMWARM warm total $(since "$t0" "$(now)")s"
xcrun simctl shutdown all 2>/dev/null || true
booted=$(xcrun simctl list devices -j | $JQ '[.devices[][] | select(.state != "Shutdown")] | length')
[ "$booted" = 0 ] || { echo "SIMWARM $booted devices still booted" >&2; exit 1; }
echo "SIMWARM device set $(du -sh "$HOME/Library/Developer/CoreSimulator" | cut -f1)"
