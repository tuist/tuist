#!/bin/bash
# Experiment: in a clone with a new serial, times booting each named simulator
# as `runner`: when bootstatus finished, when the guest went quiet (under 60%
# CPU for 15 s), and the CPU-seconds until then. Lines start with SIMWARM.
# Usage: measure.sh <label> '<runtime id>|<device name>'...
set -uo pipefail
JQ=/opt/homebrew/bin/jq
LABEL=$1; shift
now() { perl -MTime::HiRes=time -e 'printf "%.1f", time'; }
cpu() { ps -A -o %cpu= | awk '{s+=$1} END {printf "%d", s}'; }

echo "SIMWARM $LABEL serial $(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}') user $(id -un)"
# Let the boot settle and the runtimes mount before the first measurement.
sleep 60
xcrun simctl runtime list -j | $JQ -r --arg l "$LABEL" '.[] | "SIMWARM \($l) runtime \(.runtimeIdentifier) \(.kind) \(.mountPath)"'
for spec in "$@"; do
  rt=${spec%%|*}
  name=${spec#*|}
  udid=$(xcrun simctl list devices -j | $JQ -r --arg rt "$rt" --arg n "$name" '.devices[$rt][]? | select(.name == $n) | .udid' | head -n1)
  [ -n "$udid" ] || { echo "SIMWARM $LABEL missing: $name on $rt"; continue; }
  data="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data"
  before=$(du -sh "$data" 2>/dev/null | cut -f1)
  rm -f /tmp/simwarm-booted
  s=$(now)
  ( xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1; now > /tmp/simwarm-booted ) &
  cs=0; quiet=0; i=0
  while [ "$quiet" -lt 3 ] && [ "$i" -lt 72 ]; do
    sleep 5; i=$((i + 1)); c=$(cpu); cs=$((cs + c * 5 / 100))
    if [ -f /tmp/simwarm-booted ] && [ "$c" -lt 60 ]; then quiet=$((quiet + 1)); else quiet=0; fi
  done
  wait
  b=$(perl -e "printf '%.1f', $(cat /tmp/simwarm-booted 2>/dev/null || echo 0) - $s")
  q=$(perl -e "printf '%.1f', $(now) - $s - 15")
  echo "SIMWARM $LABEL $name: data before $before, boot ${b}s, quiet at ${q}s, cpu-seconds $cs"
  xcrun simctl shutdown "$udid" 2>/dev/null
  sleep 10
done
