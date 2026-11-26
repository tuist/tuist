package hostinfo

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

func TestParseMeminfo(t *testing.T) {
	total, available := ParseMeminfo("MemTotal:       131072000 kB\nMemFree:        1000 kB\nMemAvailable:   65536000 kB\nBuffers: 1 kB\n")
	if total != 131072000*1024 || available != 65536000*1024 {
		t.Fatalf("got %d %d", total, available)
	}
	if total, _ := ParseMeminfo("garbage"); total != 0 {
		t.Fatal("expected zero on garbage")
	}
}

func TestParseResolvConf(t *testing.T) {
	got := ParseResolvConf("# comment\nsearch tuist-sandboxes.svc.cluster.local svc.cluster.local\nnameserver 10.128.0.10\nnameserver   fd00::1\noptions ndots:5\n")
	if len(got) != 2 || got[0] != "10.128.0.10" || got[1] != "fd00::1" {
		t.Fatalf("got %v", got)
	}
}

func TestParseCgroupValue(t *testing.T) {
	if value, ok := ParseCgroupValue("21474836480\n"); !ok || value != 21474836480 {
		t.Fatalf("limit = %d, %v", value, ok)
	}
	if _, ok := ParseCgroupValue("max\n"); ok {
		t.Fatal("max must report no limit")
	}
	if _, ok := ParseCgroupValue(""); ok {
		t.Fatal("empty must report no limit")
	}
}

func TestParseCgroupPath(t *testing.T) {
	path := ParseCgroupPath("0::/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod3f87.slice/cri-containerd-0d01.scope\n")
	if path != "/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod3f87.slice/cri-containerd-0d01.scope" {
		t.Fatalf("path = %q", path)
	}
	if path := ParseCgroupPath("0::/\n"); path != "/" {
		t.Fatalf("private namespace path = %q", path)
	}
	if path := ParseCgroupPath(""); path != "/" {
		t.Fatalf("missing line path = %q", path)
	}
}

func TestReadCgroupValueWalksUpToTheNearestLimit(t *testing.T) {
	root := t.TempDir()
	leaf := "/kubepods.slice/pod.slice/container.scope"
	if err := os.MkdirAll(filepath.Join(root, leaf), 0o755); err != nil {
		t.Fatal(err)
	}
	write := func(path, content string) {
		if err := os.WriteFile(filepath.Join(root, path), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(leaf, "memory.max"), "max\n")
	write(filepath.Join(leaf, "memory.current"), "1048576\n")
	write("/kubepods.slice/pod.slice/memory.max", "21474836480\n")

	if value, ok := ReadCgroupValue(root, leaf, "memory.max", true); !ok || value != 21474836480 {
		t.Fatalf("limit = %d, %v; want the pod slice's limit", value, ok)
	}
	if value, ok := ReadCgroupValue(root, leaf, "memory.current", false); !ok || value != 1048576 {
		t.Fatalf("current = %d, %v", value, ok)
	}
	if _, ok := ReadCgroupValue(root, leaf, "memory.max", false); ok {
		t.Fatal("a leaf without a limit must not report one when not walking up")
	}
	if _, ok := ReadCgroupValue(root, "/", "memory.max", true); ok {
		t.Fatal("a root without the file must report no limit")
	}
}

func TestReclaimCgroupAsksForTheExcessOverTarget(t *testing.T) {
	root := t.TempDir()
	leaf := "/kubepods.slice/pod.slice/container.scope"
	if err := os.MkdirAll(filepath.Join(root, leaf), 0o755); err != nil {
		t.Fatal(err)
	}
	write := func(name, content string) {
		if err := os.WriteFile(filepath.Join(root, leaf, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("memory.max", "17179869184\n")
	write("memory.current", "10737418240\n")
	write("memory.reclaim", "")

	got := ReclaimCgroup(root, leaf, 8589934592)
	asked, err := os.ReadFile(filepath.Join(root, leaf, "memory.reclaim"))
	if err != nil {
		t.Fatalf("memory.reclaim not written: %v", err)
	}
	if string(asked) != "2147483648" {
		t.Fatalf("asked to reclaim %q, want the 2 GiB above target", asked)
	}
	if got.MemoryBytes != 17179869184 || got.UsedBytes != 10737418240 {
		t.Fatalf("result = %+v", got)
	}
}

func TestReclaimCgroupLeavesACgroupUnderTargetAlone(t *testing.T) {
	root := t.TempDir()
	leaf := "/container.scope"
	if err := os.MkdirAll(filepath.Join(root, leaf), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, leaf, "memory.current"), []byte("1048576\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	ReclaimCgroup(root, leaf, 8589934592)
	if _, err := os.Stat(filepath.Join(root, leaf, "memory.reclaim")); !os.IsNotExist(err) {
		t.Fatalf("memory.reclaim must not be written under target, stat err = %v", err)
	}
}

func TestSnapshotCompatFollowsTheCPUKernelAndFirecracker(t *testing.T) {
	cpu := func(model, microcode, flags string) string {
		return "processor\t: 0\nvendor_id\t: AuthenticAMD\ncpu family\t: 26\nmodel\t\t: " + model +
			"\nmodel name\t: AMD Ryzen 9 9950X 16-Core Processor\nstepping\t: 0\nmicrocode\t: " + microcode +
			"\nflags\t\t: " + flags + "\n\nprocessor\t: 1\nvendor_id\t: other\n"
	}
	base := ParseSnapshotCompat(cpu("68", "0xb404032", "fpu avx512f"), "6.8.0-149-generic\n", "1.16.2")
	if got := ParseSnapshotCompat(cpu("68", "0xb404032", "fpu avx512f"), "6.8.0-149-generic", "1.16.2"); got != base {
		t.Fatal("a trailing newline changed the key")
	}
	for name, other := range map[string]string{
		"model":     ParseSnapshotCompat(cpu("69", "0xb404032", "fpu avx512f"), "6.8.0-149-generic", "1.16.2"),
		"microcode": ParseSnapshotCompat(cpu("68", "0xb404035", "fpu avx512f"), "6.8.0-149-generic", "1.16.2"),
		"flags":     ParseSnapshotCompat(cpu("68", "0xb404032", "fpu"), "6.8.0-149-generic", "1.16.2"),
		// KVM's MSR handling changes within one upstream version: snapshots
		// of 6.8.0-151 did not load on 6.8.0-149.
		"distribution build": ParseSnapshotCompat(cpu("68", "0xb404032", "fpu avx512f"), "6.8.0-151-generic", "1.16.2"),
		"kernel":             ParseSnapshotCompat(cpu("68", "0xb404032", "fpu avx512f"), "6.11.0-1-generic", "1.16.2"),
		"firecracker":        ParseSnapshotCompat(cpu("68", "0xb404032", "fpu avx512f"), "6.8.0-149-generic", "1.17.0"),
	} {
		if other == base {
			t.Errorf("a different %s kept the key", name)
		}
	}
}

// A cgroupfs stand-in: the files setupVMCgroups reads and writes. The
// kernel's side (moving processes, enforcing weights) is not simulated.
func fakeCgroup(t *testing.T, controllers string) (root string) {
	t.Helper()
	root = t.TempDir()
	dir := filepath.Join(root, "pod", "container")
	if err := os.MkdirAll(filepath.Join(dir, "vm-left-behind"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{"cgroup.controllers": controllers, "cgroup.procs": "", "cgroup.subtree_control": "", "memory.current": "4096"} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() { containerCgroup.Store(nil) })
	return root
}

func TestSetupVMCgroupsWeighsVMsByTheirGuarantee(t *testing.T) {
	root := fakeCgroup(t, "cpuset cpu io memory pids")
	dir := filepath.Join(root, "pod", "container")

	cgroups, err := setupVMCgroups(root, "/pod/container", daemonCgroup, 250)
	if err != nil {
		t.Fatal(err)
	}
	read := func(path string) string {
		data, _ := os.ReadFile(filepath.Join(dir, path))
		return string(data)
	}
	if got := read("cgroup.subtree_control"); got != "+cpu +memory" {
		t.Fatalf("subtree_control = %q", got)
	}
	if got := read("sandboxd/cpu.weight"); got != "25" {
		t.Fatalf("daemon weight = %q", got)
	}
	if _, err := os.Stat(filepath.Join(dir, "vm-left-behind")); !os.IsNotExist(err) {
		t.Fatalf("a leftover VM cgroup survived setup: %v", err)
	}
	// Memory is still read from the container's cgroup, which holds the
	// guests, not from the daemon's leaf.
	if path, _ := ownCgroup(); path != "/pod/container" {
		t.Fatalf("own cgroup = %q", path)
	}

	for id, milli := range map[string]uint64{"quarter": 250, "four": 4000, "tiny": 1} {
		file, err := cgroups.Open(id, milli, milli<<20)
		if err != nil {
			t.Fatal(err)
		}
		file.Close()
		if got, want := read("vm-"+id+"/cpu.weight"), strconv.FormatUint(CPUWeight(milli), 10); got != want {
			t.Fatalf("%s weight = %q, want %q", id, got, want)
		}
		// Its guest memory is protected from the container's reclaim.
		if got, want := read("vm-"+id+"/memory.low"), strconv.FormatUint(milli<<20, 10); got != want {
			t.Fatalf("%s memory.low = %q, want %q", id, got, want)
		}
	}
	// Weights keep the guarantees' proportions: four cores weigh sixteen
	// quarter cores, and the kernel's minimum of 1 bounds the smallest.
	if CPUWeight(4000) != 16*CPUWeight(250) || CPUWeight(1) != 1 || CPUWeight(10_000_000) != 10000 {
		t.Fatalf("weights %d %d %d %d", CPUWeight(250), CPUWeight(4000), CPUWeight(1), CPUWeight(10_000_000))
	}
	// The VM's memory is read from its own cgroup.
	if err := os.WriteFile(filepath.Join(dir, "vm-four", "memory.current"), []byte("123456\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got, ok := cgroups.MemoryCurrent("four"); !ok || got != 123456 {
		t.Fatalf("memory.current = %d, %v", got, ok)
	}
	if _, ok := cgroups.MemoryCurrent("never-opened"); ok {
		t.Fatal("read the memory of a VM without a cgroup")
	}
	// cgroupfs removes a cgroup's interface files with it; a plain
	// directory needs them gone first.
	for _, name := range []string{"cpu.weight", "memory.low", "memory.current"} {
		_ = os.Remove(filepath.Join(dir, "vm-four", name))
	}
	if err := cgroups.Remove("four"); err != nil {
		t.Fatal(err)
	}
	if err := cgroups.Remove("never-opened"); err != nil {
		t.Fatalf("removing a missing cgroup: %v", err)
	}
}

// Without the memory controller VMs still get their CPU weights, and
// memory is neither protected nor read per VM.
func TestVMCgroupsWithoutTheMemoryController(t *testing.T) {
	root := fakeCgroup(t, "cpu pids")
	dir := filepath.Join(root, "pod", "container")
	cgroups, err := setupVMCgroups(root, "/pod/container", daemonCgroup, 250)
	if err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(filepath.Join(dir, "cgroup.subtree_control")); string(data) != "+cpu" {
		t.Fatalf("subtree_control = %q", data)
	}
	file, err := cgroups.Open("vm", 1000, 1<<30)
	if err != nil {
		t.Fatal(err)
	}
	file.Close()
	if _, err := os.Stat(filepath.Join(dir, "vm-vm", "memory.low")); !os.IsNotExist(err) {
		t.Fatalf("wrote memory.low without the memory controller: %v", err)
	}
	if _, ok := cgroups.MemoryCurrent("vm"); ok {
		t.Fatal("read per-VM memory without the memory controller")
	}
}

func TestSetupVMCgroupsNeedsTheCPUController(t *testing.T) {
	root := fakeCgroup(t, "memory pids")
	if _, err := setupVMCgroups(root, "/pod/container", daemonCgroup, 250); err == nil {
		t.Fatal("set up without a cpu controller")
	}
	if containerCgroup.Load() != nil {
		t.Fatal("a failed setup redirected memory reads")
	}
}

func TestAdoptVMCgroupsUsesTheVMMContainersCgroup(t *testing.T) {
	root := fakeCgroup(t, "cpuset cpu io memory pids")
	dir := filepath.Join(root, "pod", "container")
	if _, err := setupVMCgroups(root, "/pod/container", "vmm", 250); err != nil {
		t.Fatal(err)
	}
	// A VM leaf still holding a process: rmdir fails, as on cgroupfs.
	if err := os.MkdirAll(filepath.Join(dir, "vm-running"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "vm-running", "cgroup.procs"), []byte("42"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "vm-gone"), 0o755); err != nil {
		t.Fatal(err)
	}
	containerCgroup.Store(nil)

	cgroups, err := adoptVMCgroups(root, "/pod/container")
	if err != nil {
		t.Fatal(err)
	}
	if !cgroups.memory {
		t.Fatal("adopted cgroups lost per-VM memory")
	}
	if _, err := os.Stat(filepath.Join(dir, "vm-gone")); !os.IsNotExist(err) {
		t.Fatalf("an empty VM leaf survived adoption: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "vm-running")); err != nil {
		t.Fatalf("a VM leaf in use was removed: %v", err)
	}
	if path, _ := ownCgroup(); path != "/pod/container" {
		t.Fatalf("memory is read from %q, not the vmm container's cgroup", path)
	}
}

func TestAdoptVMCgroupsRefusesACgroupWithoutCPU(t *testing.T) {
	root := fakeCgroup(t, "cpuset cpu io memory pids")
	if _, err := adoptVMCgroups(root, "/pod/container"); err == nil {
		t.Fatal("adopted a cgroup that delegates no cpu controller")
	}
}
