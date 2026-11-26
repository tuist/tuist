#!/bin/bash
# Reproduces two jobs on one stacked volume without a VM: write through
# [base, overlay1], then read through [base, overlay1, overlay2].
set -u
d=$(mktemp -d); cd "$d"
diskutil image 2>&1 | head -30
diskutil image create blank --fs APFS --format ASIF --size 1G --volumeName Chain base.asif
/tmp/dik-make "$d/base.asif" "" "$d/overlay1.asif"
echo "== attach overlay1 (stack base+overlay1)"
diskutil image attach "$d/overlay1.asif" 2>&1; diskutil image info "$d/overlay1.asif" 2>&1 | head -20
m=$(mount | awk '/Chain/ {print $3}'); echo "mounted at: $m"
if [ -n "$m" ]; then head -c 50000000 /dev/urandom > "$m/payload"; shasum "$m/payload"; df -k "$m"; diskutil eject "$m" || hdiutil detach "$m"; fi
ls -la "$d"
/tmp/dik-make "$d/base.asif" "$d/overlay1.asif" "$d/overlay2.asif"
echo "== attach overlay2 (stack base+overlay1+overlay2)"
diskutil image attach "$d/overlay2.asif" 2>&1
m=$(mount | awk '/Chain/ {print $3}'); echo "mounted at: $m"; [ -n "$m" ] && { ls -la "$m"; df -k "$m"; shasum "$m/payload" 2>&1; }
