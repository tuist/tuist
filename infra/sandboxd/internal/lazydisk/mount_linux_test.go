//go:build linux

package lazydisk

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Needs root and /dev/fuse, as sandboxd has on a node.
func TestMountServesTheImageAsAFile(t *testing.T) {
	if !Supported() {
		t.Skip("mounting FUSE needs root and /dev/fuse")
	}
	want := image(t)
	src := &source{data: bytes.Clone(want), chunk: 65536, fail: -1}
	im := newImage(t, src)
	path := filepath.Join(t.TempDir(), "rootfs.ext4")
	if err := os.WriteFile(path, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	mount, err := MountImage(path, im, 1000, 1000)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Size() != int64(len(want)) || !info.Mode().IsRegular() {
		t.Fatalf("the mount shows %v, %v", info, err)
	}
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	got := make([]byte, 4096)
	if _, err := f.ReadAt(got, 7*65536-100); err != nil || !bytes.Equal(got, want[7*65536-100:7*65536+3996]) {
		t.Fatalf("read through the mount: %v", err)
	}
	if src.fetches.Load() != 2 {
		t.Fatalf("a read of two chunks fetched %d", src.fetches.Load())
	}
	if _, err := f.WriteAt([]byte("written"), 100); err != nil {
		t.Fatal(err)
	}
	copy(want[100:], "written")
	if err := im.Fill(2); err != nil {
		t.Fatal(err)
	}
	if err := mount.Detach(); err != nil {
		t.Fatal(err)
	}
	// The open file keeps serving after the detach.
	if _, err := f.ReadAt(got, 0); err != nil || !bytes.Equal(got, want[:4096]) {
		t.Fatalf("read after the detach: %v", err)
	}
	f.Close()
	select {
	case <-mount.Done():
	case <-time.After(10 * time.Second):
		t.Fatal("the mount must end once its last user closes it")
	}
	if info, _ := os.Stat(path); info.Size() != 0 {
		t.Fatal("the path must show the file under the mount again")
	}
}
