#!/bin/sh
# Diagnostic intervention in disposable benchmark guests only. The first three
# cycles are controls; the next three purge disk caches, keeping the simulator
# and live-memory sentinel running. Never use this as a production pause hook.
set -eu
counter=/tmp/tuist-resume-fixture/reclaim-cycle
cycle=0
if [ -f "$counter" ]; then cycle=$(cat "$counter"); fi
cycle=$((cycle + 1))
printf '%s\n' "$cycle" > "$counter"
printf 'TUIST_RECLAIM cycle=%s condition=before\n' "$cycle"
/usr/bin/vm_stat
/usr/sbin/sysctl vm.swapusage
if [ "$cycle" -gt 3 ]; then
  /usr/bin/time -p sudo -n /usr/sbin/purge
  printf 'TUIST_RECLAIM cycle=%s condition=after\n' "$cycle"
  /usr/bin/vm_stat
  /usr/sbin/sysctl vm.swapusage
fi
