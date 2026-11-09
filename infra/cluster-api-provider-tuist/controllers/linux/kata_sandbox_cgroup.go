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

// With static_sandbox_resource_mgmt Kata sizes the VM once, at sandbox
// creation, from the sandbox resources the kubelet passes: the Pod-level
// `.spec.resources` budget when the Pod has one, otherwise the sum of its
// containers' limits. Without it Kata hotplugs every container's limit, and
// under a Pod-level budget each container inherits the whole budget as its
// limit: on staging a 4 CPU / 6Gi Pod with a dind sidecar booted a 9 vCPU,
// ~14.5 GiB guest inside an 8.5 GiB Pod cgroup. With it the same Pod gets
// 5 vCPUs and ~7.8 GiB (Kata's default 1 vCPU and 2 GiB plus the budget).
//
// Only hosts running the pod-level resource managers write it
// (podLevelResourceManagers), which a fresh v1.36 join is. The shim reads it
// when it creates a sandbox.
const kataStaticSandboxDropInPath = "/opt/kata/share/defaults/kata-containers/config.d/50-tuist-static-sandbox.toml"

const kataStaticSandboxDropIn = `[runtime]
static_sandbox_resource_mgmt = true
`

func kataStaticSandboxSetup(sudo string) string {
	return fmt.Sprintf(`%sbash -s <<'TUIST_KATA_STATIC_SANDBOX'
set -euo pipefail
install -d %s
cat > %s <<'TUIST_KATA_STATIC_SANDBOX_DROPIN'
%sTUIST_KATA_STATIC_SANDBOX_DROPIN
TUIST_KATA_STATIC_SANDBOX
`, sudo, "/opt/kata/share/defaults/kata-containers/config.d", kataStaticSandboxDropInPath, kataStaticSandboxDropIn)
}
