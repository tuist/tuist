package vm

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

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

func TestReflink(t *testing.T) {
	dir := t.TempDir()
	src, dst := filepath.Join(dir, "src"), filepath.Join(dir, "clone")
	if err := os.WriteFile(src, []byte("content"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Reflink(src, dst); err != nil {
		// Linux CI can use ext4 or tmpfs. Verify that the real helper refuses
		// an unsupported filesystem instead of silently copying a VM disk.
		if !errors.Is(err, syscall.EOPNOTSUPP) && !errors.Is(err, syscall.ENOTTY) {
			t.Fatal(err)
		}
		if data, readErr := os.ReadFile(dst); readErr != nil && !errors.Is(readErr, os.ErrNotExist) {
			t.Fatal(readErr)
		} else if len(data) != 0 {
			t.Fatal("unsupported reflink copied data")
		}
		t.Log("verified unsupported filesystem fails without copying")
	} else {
		data, err := os.ReadFile(dst)
		if err != nil || string(data) != "content" {
			t.Fatalf("clone content %q: %v", data, err)
		}
		if err := os.WriteFile(dst, []byte("changed"), 0o644); err != nil {
			t.Fatal(err)
		}
		// Replacing an existing clone must also work.
		if err := Reflink(src, dst); err != nil {
			t.Fatal(err)
		}
		data, err = os.ReadFile(dst)
		if err != nil || string(data) != "content" {
			t.Fatalf("replacement clone content %q: %v", data, err)
		}
	}
	data, err := os.ReadFile(src)
	if err != nil || string(data) != "content" {
		t.Fatalf("clone modified the source: %q: %v", data, err)
	}
}

func TestCappedLogStartsOverPastTheLimitAndRefusesSymlinks(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, LogFileName)
	log, err := openCappedLog(path, 1024)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 100; i++ {
		if _, err := log.Write([]byte(strings.Repeat("z", 99) + "\n")); err != nil {
			t.Fatal(err)
		}
	}
	if err := log.Close(); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Size() > 1024 {
		t.Fatalf("log grew to %d bytes past its 1024 byte cap", info.Size())
	}
	if !strings.Contains(LogTail(path, 4096), "truncated") {
		t.Fatal("a restarted log does not say it was truncated")
	}

	target := filepath.Join(dir, "elsewhere")
	if err := os.WriteFile(target, []byte("secret"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "linked.log")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if _, err := openCappedLog(link, 1024); err == nil {
		t.Fatal("opened a log through a symlink")
	}
	if tail := LogTail(link, 4096); tail != "" {
		t.Fatalf("LogTail followed a symlink and returned %q", tail)
	}
}

func TestParseStatCPUTime(t *testing.T) {
	stat := "4242 (fire (cracker)) S 1 4242 4242 0 -1 4194560 812 0 0 0 1234 566 0 0 20 0 9 0 51 2147483648 3000 18446744073709551615 0 0 0 0 0 0 0 0 0 0 0 0 17 3 0 0 0 0 0\n"
	if got, ok := parseStatCPUTime(stat); !ok || got != 18*time.Second {
		t.Fatalf("got %v %v, want 18s", got, ok)
	}
	for _, bad := range []string{"", "4242 fire S 1", "4242 (fire) S 1 2 3"} {
		if _, ok := parseStatCPUTime(bad); ok {
			t.Fatalf("parsed %q", bad)
		}
	}
}

func TestParseSmapsRollup(t *testing.T) {
	text := `55d0c0000000-7ffd2a3f0000 ---p 00000000 00:00 0                          [rollup]
Rss:             6291456 kB
Pss:             5767168 kB
Pss_Dirty:       4194304 kB
Pss_Anon:        4194304 kB
Pss_File:        1048576 kB
Pss_Shmem:        524288 kB
Shared_Clean:    1048576 kB
Anonymous:       4194304 kB
Swap:                  0 kB
`
	got, ok := parseSmapsRollup(text)
	if !ok || got.AnonBytes != 4<<30 || got.FileBytes != 3<<29 {
		t.Fatalf("got %+v %v, want 4 GiB anon and 1.5 GiB file", got, ok)
	}
	if _, ok := parseSmapsRollup("Rss: 12 kB\n"); ok {
		t.Fatal("parsed a rollup without Pss_Anon (kernel before 5.x)")
	}
}

func TestProcessCPUTimeOfAMissingProcess(t *testing.T) {
	if _, ok := vcpuCPUTime("/proc", 0); ok {
		t.Fatal("read a CPU time for pid 0")
	}
}

func TestCPUTimeCountsOnlyTheVCPUThreads(t *testing.T) {
	proc := t.TempDir()
	stat := func(utime, stime int) string {
		return fmt.Sprintf("1 (x) S 1 1 1 0 -1 0 0 0 0 0 %d %d 0 0 20 0 1 0 1 0 0\n", utime, stime)
	}
	write := func(path, data string) {
		if err := os.MkdirAll(filepath.Dir(filepath.Join(proc, path)), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(proc, path), []byte(data), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// As read on a staging node: the VMM thread emulates devices, the
	// vCPU threads run the guest.
	write("42/stat", stat(100, 900))
	write("42/task/42/comm", "firecracker\n")
	write("42/task/42/stat", stat(50, 350))
	write("42/task/43/comm", "fc_api\n")
	write("42/task/43/stat", stat(0, 10))
	write("42/task/44/comm", "fc_vcpu 0\n")
	write("42/task/44/stat", stat(10, 90))
	write("42/task/45/comm", "fc_vcpu 1\n")
	write("42/task/45/stat", stat(40, 360))
	if got, ok := vcpuCPUTime(proc, 42); !ok || got != 5*time.Second {
		t.Fatalf("got %v %v, want the vCPU threads' 5s", got, ok)
	}

	// Without vCPU threads it falls back to the whole process.
	write("7/stat", stat(100, 200))
	write("7/task/7/comm", "vmm\n")
	write("7/task/7/stat", stat(100, 200))
	if got, ok := vcpuCPUTime(proc, 7); !ok || got != 3*time.Second {
		t.Fatalf("got %v %v, want the process's 3s", got, ok)
	}
}
