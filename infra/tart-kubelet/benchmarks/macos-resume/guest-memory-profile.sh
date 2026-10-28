#!/bin/sh
# Run immediately before each snapshot, outside the measured suspend/restore.
# Preserve vm_stat categories verbatim: inactive and file-backed pages overlap,
# and "stored in compressor" is logical memory, not its physical footprint.
set -eu
printf 'TUIST_MEMORY_PROFILE_BEGIN\n'
/bin/date -u '+observed_at=%Y-%m-%dT%H:%M:%SZ'
/usr/sbin/sysctl hw.memsize vm.swapusage
/usr/bin/vm_stat
# Aggregate only; do not record command arguments or guest environment values.
/bin/ps -axo rss= | /usr/bin/awk '{total += $1} END {printf "process_rss_sum_kib=%d\n", total}'
printf 'TUIST_MEMORY_PROFILE_END\n'
