//go:build darwin

package cachevolumes

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"golang.org/x/sys/unix"
)

// A Tart VM's virtio-fs server runs in a sandbox scoped to the share and opens
// files by inode. sandbox-exec with the private images directory denied, and
// an open through /.vol, does the same.
func TestAPFSSharedImageOpensFromASandboxScopedToTheShare(t *testing.T) {
	if _, err := exec.LookPath("sandbox-exec"); err != nil {
		t.Skip("sandbox-exec unavailable")
	}
	b, _ := newAPFS(t)
	root, err := filepath.EvalSymlinks(b.Root)
	if err != nil {
		t.Fatal(err)
	}
	b.Root = root
	profile := filepath.Join(t.TempDir(), "share.sb")
	rules := fmt.Sprintf("(version 1)\n(allow default)\n(deny file-read* file-write* (subpath %q))\n", filepath.Join(root, "images"))
	if err := os.WriteFile(profile, []byte(rules), 0600); err != nil {
		t.Fatal(err)
	}
	for i := range 10 {
		slot := Slot{Identity: identity(first), PodUID: fmt.Sprintf("pod%d", i)}
		slot.ID = fmt.Sprintf("00000000-0000-0000-0000-%012d", i)
		path := apfsPath(t, b, slot)
		if err := b.Attach(context.Background(), slot, path); err != nil {
			t.Fatal(err)
		}
		exposed := filepath.Join(path, "cache.sparseimage")
		var stat unix.Stat_t
		if err := unix.Stat(exposed, &stat); err != nil {
			t.Fatal(err)
		}
		// The host measures and checks branches by their private name while VMs run.
		_, _ = os.Lstat(b.image(slot))

		byInode := fmt.Sprintf("/.vol/%d/%d", stat.Dev, stat.Ino)
		if out, err := exec.Command("sandbox-exec", "-f", profile, "cat", byInode).CombinedOutput(); err != nil {
			t.Fatalf("attach %d: the VM's sandbox could not open its shared image: %v (%s)", i, err, out)
		}
	}
}
