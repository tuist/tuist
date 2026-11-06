package linux

import "fmt"

// Kata only resolves the systemd cgroup path kubelet hands it
// (kubepods-<qos>-pod<uid>.slice:cri-containerd:<id>) when sandbox_cgroup_only
// is on. With the default (false) it treats that path as a cgroupfs one
// (NewSandboxResourceController in kata 3.30's resourcecontrol/cgroups.go), so
// QEMU runs in a directory of that literal name at the cgroup root, and
// virtiofsd and the shim in /kata_overhead/<id>. Both sit outside kubepods.slice,
// so the kubelet's Pod limits and cpusets never apply to the VM, and neither
// directory is removed when the sandbox exits: measured on staging, 3,351 of
// each after 8 days, and about 65k of each on the Hetzner node that hit ENOSPC.
// containerd's SystemdCgroup = true on the kata handler does not change this.
//
// Turning it on puts the shim, virtiofsd and QEMU in a systemd scope under the
// Pod's slice, which systemd removes when the sandbox exits. Kata writes only a
// cpuset there; the limits are the Pod slice's, which the RuntimeClass's
// podFixed overhead (250m, 2560Mi) budgets for.
//
// The shim reads this when it creates a sandbox, so running sandboxes keep the
// cgroup they started in. The rmdirs then clear what earlier sandboxes leaked:
// rmdir refuses a cgroup that still holds a process or a child, so the ones a
// running sandbox uses stay.
// Keep in sync with the Hetzner worker's cloud-init files.
const kataSandboxCgroupDropInPath = "/opt/kata/share/defaults/kata-containers/config.d/50-tuist-sandbox-cgroup.toml"

const kataSandboxCgroupDropIn = `[runtime]
sandbox_cgroup_only = true
`

func kataSandboxCgroupSetup(sudo string) string {
	return fmt.Sprintf(`%sbash -s <<'TUIST_KATA_SANDBOX_CGROUP'
set -euo pipefail
install -d %s
cat > %s <<'TUIST_KATA_SANDBOX_CGROUP_DROPIN'
%sTUIST_KATA_SANDBOX_CGROUP_DROPIN
find /sys/fs/cgroup -maxdepth 1 -type d -name 'kubepods-*:cri-containerd:*' -exec rmdir {} + 2>/dev/null || true
find /sys/fs/cgroup/kata_overhead -mindepth 1 -maxdepth 1 -type d -exec rmdir {} + 2>/dev/null || true
TUIST_KATA_SANDBOX_CGROUP
`, sudo, "/opt/kata/share/defaults/kata-containers/config.d", kataSandboxCgroupDropInPath, kataSandboxCgroupDropIn)
}
