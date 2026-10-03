package linux

import (
	"crypto/sha256"
	"fmt"

	corev1 "k8s.io/api/core/v1"
)

const kataSharedMemoryAnnotation = "tuist.dev/kata-shared-memory-config"

// Kata's virtio-fs backend puts guest RAM in /dev/shm. Its default half-RAM
// tmpfs ceiling is invisible to kube-scheduler and can fail KVM_RUN with EFAULT
// while the host still has ample available memory. Raising the ceiling does
// not allocate RAM; scheduling still accounts for pod requests and node reservations.
// Keep the script and unit in sync with the Hetzner worker's cloud-init files.
const kataSharedMemoryScript = `#!/bin/sh
set -eu

test "$(findmnt -n -o FSTYPE --mountpoint /dev/shm)" = tmpfs
memory_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
test "$memory_kib" -gt 0
target_bytes=$((memory_kib * 1024))
current_bytes=$(df -B1 --output=size /dev/shm | tail -n 1)

# Grow only, preserving any larger operator-defined ceiling and mount flags.
if [ "$current_bytes" -lt "$target_bytes" ]; then
  mount -o "remount,size=${memory_kib}k" /dev/shm
fi
test "$(df -B1 --output=size /dev/shm | tail -n 1)" -ge "$target_bytes"
`

const kataSharedMemoryUnit = `[Unit]
Description=Size shared memory for Kata guest RAM
RequiresMountsFor=/dev/shm
Before=containerd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tuist-kata-shared-memory
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
`

func kataSharedMemoryRevision(node *corev1.Node) string {
	return fmt.Sprintf("%x:%s", sha256.Sum256([]byte(kataSharedMemoryScript+kataSharedMemoryUnit)), node.Status.NodeInfo.BootID)
}

// Runs at bootstrap and on existing Kata hosts. Restarting this oneshot only
// verifies/grows the mount; it never restarts containerd, kubelet, or a VM.
func renderKataSharedMemoryRepairScript(opts linuxCloudInitOptions) string {
	sudo, _ := escalation(opts.BootstrapUser)
	return "#!/usr/bin/env bash\nset -euo pipefail\n" + kataSharedMemorySetup(sudo)
}

func kataSharedMemorySetup(sudo string) string {
	return fmt.Sprintf(`%sbash -s <<'TUIST_KATA_SHM_ROOT'
set -euo pipefail
install -d /usr/local/sbin
cat > /usr/local/sbin/tuist-kata-shared-memory <<'TUIST_KATA_SHM_SCRIPT'
%sTUIST_KATA_SHM_SCRIPT
chmod 0755 /usr/local/sbin/tuist-kata-shared-memory
cat > /etc/systemd/system/tuist-kata-shared-memory.service <<'TUIST_KATA_SHM_UNIT'
%sTUIST_KATA_SHM_UNIT
systemctl daemon-reload
systemctl enable tuist-kata-shared-memory.service
systemctl restart tuist-kata-shared-memory.service
TUIST_KATA_SHM_ROOT
`, sudo, kataSharedMemoryScript, kataSharedMemoryUnit)
}
