package linux

import "fmt"

// virtiofsd serves each Kata pod's rootfs and volumes to the guest, and holds
// one host file descriptor for every inode the guest kernel has cached. Its
// default budget is min(1,000,000, fs.nr_open); once that is spent it answers
// the guest's lookups and opens with EMFILE, whatever the guest process's own
// RLIMIT_NOFILE is. A job that keeps around a million files reachable (a
// ClickHouse data directory full of unmerged parts, a large node_modules tree
// plus build outputs) then fails with "Too many open files".
//
// The guest frees these descriptors as it evicts inodes, so the budget bounds
// how many inodes a pod can keep cached, and every cached inode pins host kernel
// memory. Four times the default keeps that bounded while giving jobs room.
const kataVirtiofsFileLimit = 4194304

const kataVirtiofsSysctlPath = "/etc/sysctl.d/90-tuist-kata-virtiofs.conf"

// setrlimit refuses values above fs.nr_open, so virtiofsd can only use the
// higher budget once the host allows it.
var kataVirtiofsSysctl = fmt.Sprintf("fs.nr_open = %d\n", kataVirtiofsFileLimit)

// Kata merges config.d drop-ins next to the configuration containerd points the
// kata-qemu handler at. The array replaces the stock one, so it repeats Kata's
// defaults. virtiofsd reads its arguments when a pod starts, so new pods pick
// this up without restarting containerd or touching running guests.
const kataVirtiofsDropInPath = "/opt/kata/share/defaults/kata-containers/config.d/50-tuist-virtiofs.toml"

var kataVirtiofsDropIn = fmt.Sprintf(`[hypervisor.qemu]
virtio_fs_extra_args = ["--thread-pool-size=1", "--announce-submounts", "--rlimit-nofile=%d"]
`, kataVirtiofsFileLimit)

func kataVirtiofsSetup(sudo string) string {
	return fmt.Sprintf(`%sbash -s <<'TUIST_KATA_VIRTIOFS_ROOT'
set -euo pipefail
cat > %s <<'TUIST_KATA_VIRTIOFS_SYSCTL'
%sTUIST_KATA_VIRTIOFS_SYSCTL
sysctl -p %s
test "$(cat /proc/sys/fs/nr_open)" -ge %d
install -d %s
cat > %s <<'TUIST_KATA_VIRTIOFS_DROPIN'
%sTUIST_KATA_VIRTIOFS_DROPIN
TUIST_KATA_VIRTIOFS_ROOT
`, sudo, kataVirtiofsSysctlPath, kataVirtiofsSysctl, kataVirtiofsSysctlPath, kataVirtiofsFileLimit,
		"/opt/kata/share/defaults/kata-containers/config.d", kataVirtiofsDropInPath, kataVirtiofsDropIn)
}
