package cachevolumes

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/sys/unix"
)

func links(t *testing.T, path string) uint64 {
	t.Helper()
	var stat unix.Stat_t
	if err := unix.Lstat(path, &stat); err != nil {
		t.Fatal(err)
	}
	return uint64(stat.Nlink)
}

func TestAPFSSharesTheBranchImageUnderItsOnlyName(t *testing.T) {
	b, remote := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	exposed := filepath.Join(path, "cache.sparseimage")
	if got := links(t, exposed); got != 1 {
		t.Fatalf("the shared image has %d names while its VM runs, want 1", got)
	}
	if _, err := os.Lstat(b.image(slot)); !os.IsNotExist(err) {
		t.Fatalf("the private name still exists while the VM runs: %v", err)
	}
	if err := os.WriteFile(exposed, []byte("job writes"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(exposed); string(data) != "job writes" {
		t.Fatalf("a repeated attach replaced the exposed branch: %q", data)
	}

	detached(t, path, slot.ID)
	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(b.image(slot)); string(data) != "job writes" {
		t.Fatalf("sealed %q, want the job's writes", data)
	}
	if remote.uploads != 1 {
		t.Fatal("the branch was not published")
	}
}

func TestAPFSResumesAnExposureInterruptedAfterLinking(t *testing.T) {
	b, _ := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	exposed := filepath.Join(path, "cache.sparseimage")
	if err := os.Link(exposed, b.image(slot)); err != nil {
		t.Fatal(err)
	}

	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	if got := links(t, exposed); got != 1 {
		t.Fatalf("the shared image has %d names after a resumed attach, want 1", got)
	}
}

func TestAPFSSealClaimsOnlyTheImageItExposed(t *testing.T) {
	b, remote := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	exposed := filepath.Join(path, "cache.sparseimage")
	outside := filepath.Join(t.TempDir(), "host file")
	if err := os.WriteFile(outside, []byte("host"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(exposed, filepath.Join(path, "moved")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, exposed); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)

	if err := b.Seal(slot, path); Result(err) != "replaced" {
		t.Fatal(err)
	}
	if _, err := os.Lstat(b.image(slot)); !os.IsNotExist(err) {
		t.Fatalf("claimed a file the guest put in the share: %v", err)
	}
	if remote.uploads != 0 {
		t.Fatal("published a replaced branch")
	}
}

func TestAPFSMarksPressureOnAnExposedBranch(t *testing.T) {
	b, remote := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	if !APFSHasBranch(b.Root, slot) || APFSBranchFile(b.Root, slot) != filepath.Join(path, "cache.sparseimage") {
		t.Fatal("the exposed branch is not found by its shared name")
	}
	if err := b.MarkPressure(slot); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)
	if err := b.Seal(slot, path); Result(err) != "pressure" {
		t.Fatal(err)
	}
	if remote.uploads != 0 {
		t.Fatal("published a branch written under pressure")
	}
}
