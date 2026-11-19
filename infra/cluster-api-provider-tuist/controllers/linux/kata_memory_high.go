package linux

import "fmt"

// An exclusive-CPU runner Pod is Guaranteed with a Pod-level memory limit
// (memory.max) of its budget plus the RuntimeClass's podFixed overhead. QEMU's
// guest RAM, page tables and slab fill most of that, and virtiofsd's dirty host
// page cache for the guest's file writes is charged to the same cgroup. When a
// guest writes faster than the disk takes it, the dirty and writeback pages
// cannot be reclaimed in time, and the host OOM-kills QEMU at memory.max
// (2026-11-18, 8x32 and 16x64 probes). A host-wide dirty byte cap prevented
// that but throttled every writer on the host, so it was reverted.
//
// memory.high a little below memory.max makes the kernel reclaim the Pod's page
// cache and throttle its allocations, writeback included, once usage crosses
// it, instead of killing anything. The kubelet leaves memory.high at max on a
// Guaranteed Pod (memoryThrottlingFactor 1.0 in linux_cloudinit.go), so this
// service sets it, every few seconds, on every Guaranteed Pod slice that holds
// a QEMU process: exclusive-CPU runner Pods, and nothing else on these hosts.
// Burstable runner Pods have no Pod-level limit and are left alone.
//
// The headroom has to stay below podFixed less what the guest itself needs
// above its budget (Kata's 2 GiB plus about 1 GiB of page tables and slab), or
// a guest using all of its RAM is throttled on its own memory.
const kataMemoryHighHeadroomBytes = 256 << 20

const kataMemoryHighScriptPath = "/usr/local/sbin/tuist-kata-memory-high"

var kataMemoryHighScript = fmt.Sprintf(`#!/bin/sh
# Usage: tuist-kata-memory-high [kubepods slice] [proc]
set -u
root=${1:-/sys/fs/cgroup/kubepods.slice}
proc=${2:-/proc}
headroom=%d

for pod in "$root"/kubepods-pod*.slice; do
  [ -d "$pod" ] || continue
  max=$(cat "$pod/memory.max" 2>/dev/null) || continue
  case $max in ''|*[!0-9]*) continue ;; esac
  [ "$max" -gt "$headroom" ] || continue

  vm=
  for procs in "$pod"/*/cgroup.procs; do
    [ -f "$procs" ] || continue
    while read -r pid; do
      case $(cat "$proc/$pid/comm" 2>/dev/null) in qemu-system-*) vm=1; break ;; esac
    done < "$procs"
    [ -n "$vm" ] && break
  done
  [ -n "$vm" ] || continue

  high=$((max - headroom))
  [ "$(cat "$pod/memory.high" 2>/dev/null)" = "$high" ] && continue
  echo "$high" > "$pod/memory.high" && echo "set $pod memory.high=$high (memory.max=$max)"
done
`, kataMemoryHighHeadroomBytes)

const kataMemoryHighUnit = `[Unit]
Description=Soft-limit exclusive-CPU Kata runner Pods below their memory.max
After=containerd.service

[Service]
Type=simple
ExecStart=/bin/sh -c 'while :; do /usr/local/sbin/tuist-kata-memory-high; sleep 5; done'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
`

func kataMemoryHighSetup(sudo string) string {
	return fmt.Sprintf(`%sbash -s <<'TUIST_KATA_MEMORY_HIGH_ROOT'
set -euo pipefail
install -d /usr/local/sbin
cat > %s <<'TUIST_KATA_MEMORY_HIGH_SCRIPT'
%sTUIST_KATA_MEMORY_HIGH_SCRIPT
chmod 0755 %s
cat > /etc/systemd/system/tuist-kata-memory-high.service <<'TUIST_KATA_MEMORY_HIGH_UNIT'
%sTUIST_KATA_MEMORY_HIGH_UNIT
systemctl daemon-reload
systemctl enable tuist-kata-memory-high.service
systemctl restart tuist-kata-memory-high.service
TUIST_KATA_MEMORY_HIGH_ROOT
`, sudo, kataMemoryHighScriptPath, kataMemoryHighScript, kataMemoryHighScriptPath, kataMemoryHighUnit)
}
