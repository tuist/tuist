//go:build darwin

package podagent

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

type apfsSmokeTransfer struct{}

func (apfsSmokeTransfer) Download(cachevolumes.Slot, string) error {
	panic("unexpected remote download")
}
func (apfsSmokeTransfer) Publish(cachevolumes.Slot, string, string, string) (int64, error) {
	return 1, nil
}

func TestCustomAPFSRealColdWarmIsolation(t *testing.T) {
	root := t.TempDir()
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, MinFreeBytes: 40_000_000_000, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }, Transfer: apfsSmokeTransfer{}}, Create: createCustomImage, Verify: verifyCustomImage}
	if err := backend.Init(); err != nil {
		t.Fatal(err)
	}
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa", Account: 1, Scope: strings.Repeat("a", 64), CanPublish: true, UID: 501}, PodUID: "first"}
	branch := filepath.Join(root, "pods", slot.PodUID, slot.Scope)
	if err := os.MkdirAll(branch, 0755); err != nil {
		t.Fatal(err)
	}
	if err := backend.Attach(slot, branch); err != nil {
		t.Fatal(err)
	}
	mount := t.TempDir()
	attach := func(path string) {
		t.Helper()
		if _, err := runCmd(time.Minute, "hdiutil", "attach", path, "-owners", "off", "-quiet", "-nobrowse", "-mountpoint", mount); err != nil {
			t.Fatal(err)
		}
	}
	detach := func() {
		t.Helper()
		if _, err := runCmd(time.Minute, "hdiutil", "detach", mount, "-quiet"); err != nil {
			t.Fatal(err)
		}
	}
	defer runCmd(time.Minute, "hdiutil", "detach", mount, "-force", "-quiet")
	attach(filepath.Join(branch, "cache.sparseimage"))
	if err := os.WriteFile(filepath.Join(mount, "dependency"), []byte("published"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("dependency", filepath.Join(mount, "link")); err != nil {
		t.Fatal(err)
	}
	if _, err := runCmd(time.Minute, "xattr", "-w", "dev.tuist.test", "kept", filepath.Join(mount, "dependency")); err != nil {
		t.Fatal(err)
	}
	detach()
	_ = os.WriteFile(filepath.Join(branch, ".detached"), []byte(slot.ID), 0644)
	if err := backend.Seal(slot, branch); err != nil {
		t.Fatal(err)
	}
	masters, _ := filepath.Glob(filepath.Join(root, "masters", slot.Scope, "*.img"))
	if len(masters) != 1 {
		t.Fatal(masters)
	}
	next := slot
	next.ID = "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
	next.PodUID = "second"
	next.BaseGeneration = 1
	next.ContentDigest = strings.TrimSuffix(strings.SplitN(filepath.Base(masters[0]), "-", 2)[1], ".img")
	warm := filepath.Join(root, "pods", next.PodUID, next.Scope)
	_ = os.MkdirAll(warm, 0755)
	if err := backend.Attach(next, warm); err != nil {
		t.Fatal(err)
	}
	attach(filepath.Join(warm, "cache.sparseimage"))
	if data, err := os.ReadFile(filepath.Join(mount, "link")); err != nil || string(data) != "published" {
		t.Fatal(string(data), err)
	}
	if out, err := runCmd(time.Minute, "xattr", "-p", "dev.tuist.test", filepath.Join(mount, "dependency")); err != nil || strings.TrimSpace(out) != "kept" {
		t.Fatal(out, err)
	}
	_ = os.WriteFile(filepath.Join(mount, "dependency"), []byte("private"), 0644)
	detach()
	attach(masters[0])
	if data, _ := os.ReadFile(filepath.Join(mount, "dependency")); string(data) != "published" {
		t.Fatal("master mutated", string(data))
	}
	detach()
}

func TestCustomAPFSReclaimsInterruptedInspection(t *testing.T) {
	image := filepath.Join(t.TempDir(), "cache.sparseimage")
	if err := createCustomImage(image, 20_000_000_000); err != nil {
		t.Fatal(err)
	}
	mount := image + ".mount"
	if err := os.Mkdir(mount, 0700); err != nil {
		t.Fatal(err)
	}
	if _, err := runCmd(time.Minute, "hdiutil", "attach", image, "-readonly", "-nobrowse", "-quiet", "-mountpoint", mount); err != nil {
		t.Fatal(err)
	}
	defer runCmd(time.Minute, "hdiutil", "detach", mount, "-force", "-quiet")
	if err := detachCustomInspection(image); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(mount); !os.IsNotExist(err) {
		t.Fatal("inspection mount was retained", err)
	}
	if err := detachCustomInspection(image); err != nil {
		t.Fatal(err)
	}
}
