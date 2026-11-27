#!/bin/bash
# Experiment: boots each named simulator once, waits until the guest is quiet,
# and shuts it down, then asserts nothing is left booted. Lines start with
# SIMWARM. Usage: warm.sh '<runtime id>|<device name>'...
set -euo pipefail
JQ=/opt/homebrew/bin/jq
DEVICES="$HOME/Library/Developer/CoreSimulator/Devices"
now() { perl -MTime::HiRes=time -e 'printf "%.1f", time'; }
cpu() { ps -A -o %cpu= | awk '{s+=$1} END {printf "%d", s}'; }
since() { perl -e "printf '%.1f', $2 - $1"; }

echo "SIMWARM serial $(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}') user $(id -un)"
for spec in "$@"; do
  rt=${spec%%|*}
  name=${spec#*|}
  udid=$(xcrun simctl list devices -j | $JQ -r --arg rt "$rt" --arg n "$name" '.devices[$rt][]? | select(.name == $n) | .udid' | head -n1)
  [ -n "$udid" ] || { echo "SIMWARM missing: $name on $rt" >&2; exit 1; }
  s=$(now)
  xcrun simctl bootstatus "$udid" -b >/dev/null
  b=$(now)
  quiet=0; i=0
  while [ "$quiet" -lt 3 ] && [ "$i" -lt 60 ]; do
    sleep 5; i=$((i + 1))
    if [ "$(cpu)" -lt 60 ]; then quiet=$((quiet + 1)); else quiet=0; fi
  done
  q=$(now)
  xcrun simctl shutdown "$udid"
  e=$(now)
  echo "SIMWARM warmed $name ($rt, $udid): boot $(since "$s" "$b")s settle $(since "$b" "$q")s shutdown $(since "$q" "$e")s data $(du -sh "$DEVICES/$udid/data" 2>/dev/null | cut -f1)"
done
xcrun simctl shutdown all 2>/dev/null || true
booted=$(xcrun simctl list devices -j | $JQ '[.devices[][] | select(.state != "Shutdown")] | length')
[ "$booted" = 0 ] || { echo "SIMWARM $booted devices still booted" >&2; exit 1; }
echo "SIMWARM device set $(du -sh "$HOME/Library/Developer/CoreSimulator" | cut -f1)"
