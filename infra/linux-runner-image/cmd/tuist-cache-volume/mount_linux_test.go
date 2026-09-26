//go:build linux

package main

import (
	"encoding/json"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"golang.org/x/sys/unix"
)

func TestMain(m *testing.M) {
	if len(os.Args) == 2 && os.Args[1] == "mount-worker" {
		if err := mountWorker(); err != nil {
			os.Stderr.WriteString(err.Error())
			os.Exit(1)
		}
		os.Exit(0)
	}
	if len(os.Args) == 5 && os.Args[1] == "test-bind" {
		target := os.Args[4]
		if err := unix.Mount("none", target, "tmpfs", 0, ""); err != unix.EPERM {
			os.Stderr.WriteString("client unexpectedly has mount privileges")
			os.Exit(1)
		}
		if err := bindDirectory(os.Args[2], os.Args[3], target); err != nil {
			os.Stderr.WriteString(err.Error())
			os.Exit(1)
		}
		if err := os.WriteFile(filepath.Join(target, "from-container"), []byte("retained"), 0644); err != nil {
			os.Stderr.WriteString(err.Error())
			os.Exit(1)
		}
		os.Exit(0)
	}
	os.Exit(m.Run())

}

func testMountServer(t *testing.T, root string) string {
	t.Helper()
	dir, err := os.MkdirTemp("", "mount-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	socket := filepath.Join(dir, "socket")
	listener, err := net.ListenUnix("unixpacket", &net.UnixAddr{Name: socket, Net: "unixpacket"})
	if err != nil {
		t.Fatal(err)
	}
	source, err := os.OpenRoot(root)
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			conn, err := listener.AcceptUnix()
			if err != nil {
				return
			}
			if err := mountRequest(conn, source); err != nil {
				conn.Write([]byte(err.Error()))
			} else {
				conn.Write([]byte("ok"))
			}
			conn.Close()
		}
	}()
	t.Cleanup(func() { listener.Close(); <-done; source.Close() })
	return socket
}

func TestMountBrokerRejectsSourceTraversal(t *testing.T) {
	root := t.TempDir()
	socket := testMountServer(t, root)
	for _, path := range []string{"../data", "/etc", digest("scope") + "/../data", digest("scope") + "/data/child"} {
		err := bindDirectory(socket, path, t.TempDir())
		if err == nil || !strings.Contains(err.Error(), "invalid volume source") {
			t.Fatalf("%q: %v", path, err)
		}
	}
}

func TestMountBrokerRejectsEscapingSymlinks(t *testing.T) {
	root := t.TempDir()
	scope := digest("scope")
	if err := os.Symlink(t.TempDir(), filepath.Join(root, scope)); err != nil {
		t.Fatal(err)
	}
	if err := bindDirectory(testMountServer(t, root), scope+"/data", t.TempDir()); err == nil {
		t.Fatal("accepted an escaping source")
	}
}

func TestMountBrokerRequiresNamespaceDescriptor(t *testing.T) {
	root := t.TempDir()
	source := digest("scope") + "/data"
	if err := os.MkdirAll(filepath.Join(root, source), 0755); err != nil {
		t.Fatal(err)
	}
	socket := testMountServer(t, root)
	conn, err := net.DialUnix("unixpacket", nil, &net.UnixAddr{Name: socket, Net: "unixpacket"})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	target, err := os.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	data, _ := json.Marshal(source)
	if _, _, err = conn.WriteMsgUnix(data, unix.UnixRights(int(target.Fd()), int(target.Fd())), nil); err != nil {
		t.Fatal(err)
	}
	response := make([]byte, 4096)
	n, err := conn.Read(response)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(response[:n]), "invalid mount namespace") {
		t.Fatalf("%s", response[:n])
	}
}

func TestRealBindMountPreservesPathsAndWrites(t *testing.T) {
	if os.Getenv("TUIST_TEST_BIND_MOUNTS") != "1" {
		t.Skip("requires privileged Linux test container")
	}
	root := t.TempDir()
	source := digest("scope") + "/data"
	if err := os.MkdirAll(filepath.Join(root, source), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, source, "retained"), []byte("saved"), 0644); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(t.TempDir(), "node_modules")
	if err := os.Mkdir(target, 0755); err != nil {
		t.Fatal(err)
	}
	socket := testMountServer(t, root)
	if err := bindDirectory(socket, source, target); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := unix.Unmount(target, 0); err != nil {
			t.Error(err)
		}
	})
	info, err := os.Lstat(target)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		t.Fatalf("not a directory: %v", err)
	}
	resolved, err := filepath.EvalSymlinks(target)
	if err != nil || resolved != target {
		t.Fatalf("path changed to %q: %v", resolved, err)
	}
	if data, err := os.ReadFile(filepath.Join(target, "retained")); err != nil || string(data) != "saved" {
		t.Fatalf("retained data: %v", err)
	}
	if err := os.WriteFile(filepath.Join(target, "new"), []byte("new"), 0644); err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile(filepath.Join(root, source, "new")); err != nil || string(data) != "new" {
		t.Fatalf("write-through: %v", err)
	}
}

func TestMountTargetCannotBeReplacedAfterValidation(t *testing.T) {
	if os.Getenv("TUIST_TEST_BIND_MOUNTS") != "1" {
		t.Skip("requires privileged Linux test container")
	}
	root := t.TempDir()
	source := digest("scope") + "/data"
	if err := os.MkdirAll(filepath.Join(root, source), 0755); err != nil {
		t.Fatal(err)
	}
	target := t.TempDir()
	if err := os.WriteFile(filepath.Join(target, "keep"), []byte("keep"), 0644); err != nil {
		t.Fatal(err)
	}
	err := bindDirectory(testMountServer(t, root), source, target)
	if err == nil || !strings.Contains(err.Error(), "no longer empty") {
		t.Fatalf("expected rejection, got %v", err)
	}
	if data, err := os.ReadFile(filepath.Join(target, "keep")); err != nil || string(data) != "keep" {
		t.Fatal("target was replaced")
	}
}

func TestBindIntoUnprivilegedSeparatePIDAndMountNamespace(t *testing.T) {
	if os.Getenv("TUIST_TEST_BIND_MOUNTS") != "1" {
		t.Skip("requires privileged Linux test container")
	}
	root := t.TempDir()
	source := digest("scope") + "/data"
	if err := os.MkdirAll(filepath.Join(root, source), 0755); err != nil {
		t.Fatal(err)
	}
	target := t.TempDir()
	socket := testMountServer(t, root)
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("unshare", "--mount", "--pid", "--fork", "--mount-proc", "setpriv", "--bounding-set=-sys_admin", executable, "test-bind", socket, source, target)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("unprivileged container mount: %s %v", output, err)
	}
	if data, err := os.ReadFile(filepath.Join(root, source, "from-container")); err != nil || string(data) != "retained" {
		t.Fatalf("container writes did not reach volume: %v", err)
	}
	if _, err := os.Stat(filepath.Join(target, "from-container")); !os.IsNotExist(err) {
		t.Fatalf("mount leaked into broker namespace: %v", err)
	}
}
