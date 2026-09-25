//go:build linux

package cachevolumes

import (
	"errors"
	"golang.org/x/sys/unix"
	"os"
	"os/exec"
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

func TestLinuxLocalImagesRejectsExhaustedBackingFilesystem(t *testing.T) {
	cache := os.Getenv("CACHE_VOLUME_E2E_ROOT")
	if cache == "" {
		t.Skip("requires an isolated reflink filesystem and loop/mount privileges")
	}
	root, err := os.MkdirTemp(cache, "exhaustion-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(root)
	remote := &diskTransfer{archive: filepath.Join(t.TempDir(), "remote.image")}
	b := &LocalImages{Root: root, SizeGB: 1, MinFreeBytes: 64 << 20, Transfer: remote, Mount: Mount, Unmount: Unmount, MeasureFS: MeasureFS, FreeBytes: FreeBytes}
	if err := b.Probe(); err != nil {
		t.Fatal(err)
	}
	slot := Slot{Identity: identity(first), PodUID: "seed"}
	mount := filepath.Join(root, "mount")
	if err := os.Mkdir(mount, 0700); err != nil {
		t.Fatal(err)
	}
	defer b.Delete(slot, mount)
	if err := b.Attach(slot, mount); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mount, "payload"), []byte("saved contents"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.Seal(slot, mount); err != nil {
		t.Fatal(err)
	}
	warm := slot
	warm.ID = second
	warm.BaseGeneration = remote.generation
	warm.ContentDigest = remote.content
	warmMount := filepath.Join(root, "warm")
	if err := os.Mkdir(warmMount, 0700); err != nil {
		t.Fatal(err)
	}
	defer b.Delete(warm, warmMount)
	if err := b.Attach(warm, warmMount); err != nil {
		t.Fatal(err)
	}
	fillerPath := filepath.Join(root, "filler")
	filler, err := os.Create(fillerPath)
	if err != nil {
		t.Fatal(err)
	}
	free, err := FreeBytes(root)
	if err != nil || free < 300<<20 {
		t.Fatal("insufficient isolated test capacity", free, err)
	}
	if err := unix.Fallocate(int(filler.Fd()), 0, 0, int64(free)-(96<<20)); err != nil {
		t.Fatal(err)
	}
	if err := filler.Close(); err != nil {
		t.Fatal(err)
	}
	payload := make([]byte, 256<<20)
	for i := range payload {
		payload[i] = byte(i%251 + 1)
	}
	writeErr := os.WriteFile(filepath.Join(warmMount, "payload"), payload, 0600)
	t.Logf("buffered write result: %v", writeErr)
	if err := b.Seal(warm, warmMount); err == nil {
		t.Fatal("exhausted image was not rejected")
	}
	if err := os.Remove(fillerPath); err != nil {
		t.Fatal(err)
	}
	// Freeing space and recreating the agent cannot make lost data publishable.
	restarted := &LocalImages{Root: root, Transfer: remote, Unmount: Unmount}
	if err := restarted.Seal(warm, warmMount); !errors.Is(err, ErrPoisoned) {
		t.Fatal(err)
	}
	if remote.generation != 1 {
		t.Fatal("replaced healthy master", remote.generation)
	}
	if err := restarted.Delete(warm, warmMount); err != nil {
		t.Fatal(err)
	}
	// Restore the accepted image independently and verify the prior good bytes.
	restored := filepath.Join(root, "restored.img")
	if err := remote.Download(warm, restored); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command("debugfs", "-R", "cat payload", restored).Output()
	if err != nil || string(out) != "saved contents" {
		t.Fatal("prior master damaged", string(out), err)
	}
}
