package hostinfo

import (
	"os"
	"path/filepath"
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
