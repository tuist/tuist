package vm

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
)

func TestCommandJailer(t *testing.T) {
	bin, args := Command(Spec{ID: "abc", JailBase: "/data/sandboxes/jail", FirecrackerBin: "/usr/local/bin/firecracker",
		JailerBin: "/usr/local/bin/jailer", JailerEnabled: true, UID: 10003, GID: 10003, NetNS: "sbx-abc"})
	want := "/usr/local/bin/jailer --id abc --exec-file /usr/local/bin/firecracker --uid 10003 --gid 10003 --chroot-base-dir /data/sandboxes/jail --netns /var/run/netns/sbx-abc --new-pid-ns --cgroup-version 2 -- --api-sock /run/firecracker.socket"
	if got := bin + " " + strings.Join(args, " "); got != want {
		t.Fatalf("got  %s\nwant %s", got, want)
	}
}

func TestCommandDirect(t *testing.T) {
	bin, args := Command(Spec{ID: "abc", JailBase: "/j", FirecrackerBin: "/fc", NetNS: "sbx-abc"})
	want := "ip netns exec sbx-abc /fc --id abc --api-sock /j/firecracker/abc/root/run/firecracker.socket"
	if got := bin + " " + strings.Join(args, " "); got != want {
		t.Fatalf("got  %s\nwant %s", got, want)
	}
}

func TestPathsContainEscapes(t *testing.T) {
	for _, id := range []string{"..", "../../etc", "a/../../b"} {
		got := RootDir("/data/sandboxes/jail", id)
		if !strings.HasPrefix(got, "/data/sandboxes/jail/firecracker/") {
			t.Errorf("RootDir(%q) = %q escapes the jail base", id, got)
		}
	}
	if err := ValidateID("../x"); err == nil {
		t.Error("ValidateID accepted a traversal")
	}
	if err := ValidateID("-flag"); err == nil {
		t.Error("ValidateID accepted a leading dash")
	}
}

func TestPaths(t *testing.T) {
	if got := RootDir("/data/sandboxes/jail", "s1"); got != "/data/sandboxes/jail/firecracker/s1/root" {
		t.Fatalf("root dir %s", got)
	}
	jailed := &machine{spec: Spec{JailerEnabled: true}, root: "/j/firecracker/s1/root"}
	if jailed.GuestPath(firecracker.MemPath) != "/mem" || jailed.HostPath(firecracker.MemPath) != "/j/firecracker/s1/root/mem" {
		t.Fatal("jailed path mapping")
	}
	direct := &machine{spec: Spec{}, root: "/j/firecracker/s1/root"}
	if direct.GuestPath(firecracker.MemPath) != "/j/firecracker/s1/root/mem" {
		t.Fatal("direct path mapping")
	}
	if jailed.VsockPath() != "/j/firecracker/s1/root/v.sock" {
		t.Fatal("vsock path")
	}
}

func TestValidateID(t *testing.T) {
	for _, ok := range []string{"a", "sbx-1", "0123456789abcdef", strings.Repeat("a", 64)} {
		if err := ValidateID(ok); err != nil {
			t.Fatalf("%q should be valid: %v", ok, err)
		}
	}
	for _, bad := range []string{"", "-a", "a_b", "a/b", "a b", strings.Repeat("a", 65)} {
		if err := ValidateID(bad); err == nil {
			t.Fatalf("%q should be invalid", bad)
		}
	}
}

func TestPrepareRemovesStaleSocketsAndDevices(t *testing.T) {
	root := filepath.Join(t.TempDir(), "root")
	for _, p := range []string{"run/firecracker.socket", "v.sock", "dev/kvm", "dev/net/tun"} {
		full := filepath.Join(root, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(root, "mem"), []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Prepare(root, -1, -1); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"run/firecracker.socket", "v.sock", "dev/kvm", "dev/net/tun"} {
		if Exists(filepath.Join(root, p)) {
			t.Fatalf("%s should have been removed", p)
		}
	}
	if !Exists(filepath.Join(root, "mem")) || !Exists(filepath.Join(root, "run")) {
		t.Fatal("prepare removed too much")
	}
}

func TestFileHelpers(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	if err := os.WriteFile(src, []byte("content"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link")
	if err := HardLink(src, link); err != nil {
		t.Fatal(err)
	}
	if err := HardLink(src, link); err != nil {
		t.Fatalf("hard link should replace: %v", err)
	}
	clone := filepath.Join(dir, "clone")
	if err := Reflink(src, clone); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(clone)
	if string(data) != "content" {
		t.Fatalf("clone content %q", data)
	}
	if err := os.WriteFile(clone, []byte("changed"), 0o644); err != nil {
		t.Fatal(err)
	}
	data, _ = os.ReadFile(src)
	if string(data) != "content" {
		t.Fatal("writing the clone changed the source")
	}
	sparse := filepath.Join(dir, "sparse")
	if err := Sparse(sparse, 10<<30); err != nil {
		t.Fatal(err)
	}
	if FileSize(sparse) != 10<<30 {
		t.Fatalf("sparse size %d", FileSize(sparse))
	}
	if err := Sparse(sparse, 1<<20); err != nil {
		t.Fatalf("sparse should replace: %v", err)
	}
	if FileSize(sparse) != 1<<20 {
		t.Fatalf("sparse size after replace %d", FileSize(sparse))
	}
	logPath := filepath.Join(dir, "log")
	if err := os.WriteFile(logPath, []byte("0123456789"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := LogTail(logPath, 4); got != "6789" {
		t.Fatalf("log tail %q", got)
	}
	if got := LogTail(filepath.Join(dir, "missing"), 4); got != "" {
		t.Fatalf("missing log tail %q", got)
	}
}
