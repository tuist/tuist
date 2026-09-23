//go:build linux

package cachevolumes

import (
	"os"
	"path/filepath"
	"testing"
)

type diskTransfer struct {
	archive, content string
	generation       int64
}

func (d *diskTransfer) Download(slot Slot, path string) error {
	f, err := os.Open(d.archive)
	if err != nil {
		return err
	}
	defer f.Close()
	return RestoreImage(f, path, slot.ContentDigest, 1_000_000_000)
}
func (d *diskTransfer) Publish(_ Slot, path, _, content string) (int64, error) {
	in, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	if err = os.WriteFile(d.archive, in, 0600); err != nil {
		return 0, err
	}
	d.content = content
	d.generation++
	return d.generation, nil
}
func TestLinuxLocalImagesE2E(t *testing.T) {
	root := os.Getenv("CACHE_VOLUME_E2E_ROOT")
	if root == "" {
		t.Skip("requires an isolated reflink filesystem and loop/mount privileges")
	}
	root, err := os.MkdirTemp(root, "volume-e2e-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(root) })
	remote := &diskTransfer{archive: filepath.Join(root, "remote.image")}
	makeBackend := func(host string) *LocalImages {
		b := &LocalImages{Root: filepath.Join(root, host), SizeGB: 1, MinFreeBytes: 64 << 20, Transfer: remote, Mount: Mount, Unmount: Unmount, MeasureFS: MeasureFS, FreeBytes: FreeBytes}
		if err := os.MkdirAll(b.Root, 0700); err != nil {
			t.Fatal(err)
		}
		if err := b.Probe(); err != nil {
			t.Fatal(err)
		}
		return b
	}
	firstHost := makeBackend("host-a")
	slot := Slot{Identity: identity(first), PodUID: "job-a"}
	mount := filepath.Join(root, "mount-a")
	os.Mkdir(mount, 0700)
	t.Cleanup(func() { firstHost.Delete(slot, mount) })
	if err := firstHost.Attach(slot, mount); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mount, "payload"), []byte("successful job"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, capacity, err := firstHost.Measure(slot, mount); err != nil || capacity < 900_000_000 {
		t.Fatal(capacity, err)
	}
	if err := firstHost.Seal(slot, mount); err != nil {
		t.Fatal(err)
	}
	warm := slot
	warm.ID = second
	warm.BaseGeneration = remote.generation
	warm.ContentDigest = remote.content
	warmMount := filepath.Join(root, "mount-b")
	os.Mkdir(warmMount, 0700)
	t.Cleanup(func() { firstHost.Delete(warm, warmMount) })
	if err := firstHost.Attach(warm, warmMount); err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile(filepath.Join(warmMount, "payload")); err != nil || string(data) != "successful job" {
		t.Fatal(string(data), err)
	}
	if err := os.WriteFile(filepath.Join(warmMount, "payload"), []byte("unpublished changes"), 0644); err != nil {
		t.Fatal(err)
	}
	otherHost := makeBackend("host-b")
	other := warm
	other.ID = third
	otherMount := filepath.Join(root, "mount-c")
	os.Mkdir(otherMount, 0700)
	t.Cleanup(func() { otherHost.Delete(other, otherMount) })
	if err := otherHost.Attach(other, otherMount); err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile(filepath.Join(otherMount, "payload")); err != nil || string(data) != "successful job" {
		t.Fatal("cross-host master changed", string(data), err)
	}
	// Discarding a private branch must leave the saved master usable.
	if err := firstHost.Delete(warm, warmMount); err != nil {
		t.Fatal(err)
	}
	if err := otherHost.Delete(other, otherMount); err != nil {
		t.Fatal(err)
	}
	if err := firstHost.Delete(slot, mount); err != nil {
		t.Fatal(err)
	}
}
