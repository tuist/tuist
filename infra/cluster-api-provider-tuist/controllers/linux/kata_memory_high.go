package linux

import "fmt"

// b300ad91da ran tuist-kata-memory-high on every Kata host: it set memory.high
// 256 MiB below memory.max on exclusive-CPU runner Pods, to reclaim virtiofsd's
// dirty page cache before the host OOM-killed QEMU. It could not reclaim guest
// RAM, which is shmem, and a probe was still killed (2026-11-19). Exclusive
// pools now get a podFixed sized with the guest instead (kata-qemu-<size>
// RuntimeClasses, docs/exclusive-runner-cpus.md), so the repair stops and
// removes the service on hosts that run it, and lifts the soft limit it left on
// running Pods. Drop this once every Kata host has been repaired or replaced.
const kataMemoryHighHeadroomBytes = 256 << 20

var kataMemoryHighResetScript = fmt.Sprintf(`#!/bin/sh
set -u
root=${1:-/sys/fs/cgroup/kubepods.slice}
for pod in "$root"/kubepods-pod*.slice; do
  max=$(cat "$pod/memory.max" 2>/dev/null) || continue
  case $max in ''|*[!0-9]*) continue ;; esac
  [ "$(cat "$pod/memory.high" 2>/dev/null)" = "$((max - %d))" ] || continue
  echo max > "$pod/memory.high" && echo "reset $pod memory.high=max"
done
`, kataMemoryHighHeadroomBytes)

func kataMemoryHighRemoval(sudo string) string {
	return fmt.Sprintf(`%sbash -s <<'TUIST_KATA_MEMORY_HIGH_ROOT'
set -euo pipefail
systemctl disable --now tuist-kata-memory-high.service 2>/dev/null || true
rm -f /etc/systemd/system/tuist-kata-memory-high.service /usr/local/sbin/tuist-kata-memory-high
systemctl daemon-reload
sh -s <<'TUIST_KATA_MEMORY_HIGH_RESET'
%sTUIST_KATA_MEMORY_HIGH_RESET
TUIST_KATA_MEMORY_HIGH_ROOT
`, sudo, kataMemoryHighResetScript)
}
