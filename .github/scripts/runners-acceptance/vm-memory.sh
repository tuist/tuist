#!/usr/bin/env bash
# Touch every page of the runner VM's RAM, the way a long Gradle run does with
# heap plus page cache. A Pod whose host memory limit is smaller than its Kata
# VM (exclusive CPUs with too little podFixed overhead, 2026-11-17) gets QEMU
# killed by the host here: the job never reaches `pass` and GitHub reports
# "runner lost communication", which fails the probe job.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
trap 'fail "VM memory" "a memory assertion failed at line ${LINENO}"' ERR

total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
oom_before="$(awk '/^oom_kill / {print $2}' /proc/vmstat)"

# Hold half of guest RAM as anonymous memory while the page cache fills the rest.
anon_bytes=$(( total_kb * 1024 / 2 ))
head -c "${anon_bytes}" /dev/zero | tail -c "${anon_bytes}" > /dev/null &
hog=$!
sleep 10

file="${RUNNER_TEMP:-/tmp}/vm-memory-probe"
dd if=/dev/zero of="${file}" bs=4M count=$(( total_kb / 4096 )) status=none
cat "${file}" > /dev/null
rm -f "${file}"
kill "${hog}" 2>/dev/null || true
wait 2>/dev/null || true

oom_after="$(awk '/^oom_kill / {print $2}' /proc/vmstat)"
pass "VM memory: filled ${total_kb} kB of guest RAM with anonymous memory and page cache and the VM survived (guest OOM kills: $(( oom_after - oom_before )))"
