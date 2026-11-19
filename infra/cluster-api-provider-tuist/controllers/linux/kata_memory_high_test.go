package linux

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
)

func TestKataMemoryHighSoftLimitsExclusiveCPUVMs(t *testing.T) {
	dir := t.TempDir()
	root := filepath.Join(dir, "kubepods.slice")
	proc := filepath.Join(dir, "proc")
	const gib = 1 << 30

	write := func(path, content string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// pod lays out a Pod slice holding one scope with the given process.
	pod := func(slice, max, comm string, pid int) string {
		path := filepath.Join(root, slice)
		write(filepath.Join(path, "memory.max"), max+"\n")
		write(filepath.Join(path, "memory.high"), "max\n")
		write(filepath.Join(path, "cri-containerd-abc.scope", "cgroup.procs"), strconv.Itoa(pid)+"\n")
		write(filepath.Join(proc, strconv.Itoa(pid), "comm"), comm+"\n")
		return path
	}

	exclusive := pod("kubepods-pod1.slice", strconv.Itoa(70*gib), "qemu-system-x86", 101)
	// A Guaranteed Pod under runc on the same host: no VM, nothing to protect.
	runc := pod("kubepods-pod2.slice", strconv.Itoa(1*gib), "cache-volumes", 102)
	// A Kata Pod with no Pod-level memory limit.
	unlimited := pod("kubepods-pod3.slice", "max", "qemu-system-x86", 103)
	// Burstable Pods live under their own QoS slice and are never touched.
	burstable := pod(filepath.Join("kubepods-burstable.slice", "kubepods-burstable-pod4.slice"), strconv.Itoa(40*gib), "qemu-system-x86", 104)

	run := func() {
		t.Helper()
		script := filepath.Join(dir, "memory-high")
		if err := os.WriteFile(script, []byte(kataMemoryHighScript), 0o755); err != nil {
			t.Fatal(err)
		}
		if out, err := exec.Command("/bin/sh", script, root, proc).CombinedOutput(); err != nil {
			t.Fatalf("script failed: %v\n%s", err, out)
		}
	}
	high := func(path string) string {
		t.Helper()
		b, err := os.ReadFile(filepath.Join(path, "memory.high"))
		if err != nil {
			t.Fatal(err)
		}
		return strings.TrimSpace(string(b))
	}

	run()
	want := strconv.Itoa(70*gib - kataMemoryHighHeadroomBytes)
	if got := high(exclusive); got != want {
		t.Fatalf("exclusive-CPU VM memory.high = %s, want %s (memory.max less the headroom)", got, want)
	}
	for name, path := range map[string]string{"runc": runc, "unlimited": unlimited, "burstable": burstable} {
		if got := high(path); got != "max" {
			t.Errorf("%s Pod memory.high = %s, want it left at max", name, got)
		}
	}

	// A Pod-level limit that changes (an in-place resize) is followed.
	write(filepath.Join(exclusive, "memory.max"), strconv.Itoa(36*gib)+"\n")
	run()
	if got, want := high(exclusive), strconv.Itoa(36*gib-kataMemoryHighHeadroomBytes); got != want {
		t.Fatalf("after resize memory.high = %s, want %s", got, want)
	}
}

func TestKataHostConfigCoversMemoryHigh(t *testing.T) {
	node := &corev1.Node{}
	node.Status.NodeInfo.BootID = "boot"
	before := kataHostConfigRevision(node)
	original := kataMemoryHighScript
	t.Cleanup(func() { kataMemoryHighScript = original })
	kataMemoryHighScript += "# changed\n"
	if kataHostConfigRevision(node) == before {
		t.Fatal("changing the memory.high script must re-run the repair on existing hosts")
	}

	script := renderKataHostConfigRepairScript(linuxCloudInitOptions{BootstrapUser: "ubuntu"})
	for _, want := range []string{kataMemoryHighScript, kataMemoryHighUnit, "systemctl restart tuist-kata-memory-high.service"} {
		if !strings.Contains(script, want) {
			t.Errorf("repair script is missing %q", want)
		}
	}
}
