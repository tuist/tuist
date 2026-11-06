//go:build darwin

package podagent

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

type apfsSmokeTransfer struct{}

func (apfsSmokeTransfer) Download(context.Context, cachevolumes.Slot, string) error {
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
	if err := backend.Attach(context.Background(), slot, branch); err != nil {
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
	var stat syscall.Statfs_t
	if err := syscall.Statfs(mount, &stat); err != nil {
		t.Fatal(err)
	}
	usage, _ := json.Marshal(map[string]any{"id": slot.ID, "used_bytes": int64(stat.Blocks-stat.Bfree) * int64(stat.Bsize), "capacity_bytes": int64(stat.Blocks) * int64(stat.Bsize)})
	if err := os.WriteFile(filepath.Join(branch, ".usage"), usage, 0644); err != nil {
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
	next.ImageDigest = strings.Repeat("b", 40)
	next.ContentDigest = strings.TrimSuffix(strings.SplitN(filepath.Base(masters[0]), "-", 2)[1], ".img")
	warm := filepath.Join(root, "pods", next.PodUID, next.Scope)
	_ = os.MkdirAll(warm, 0755)
	if err := backend.Attach(context.Background(), next, warm); err != nil {
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

// A guest wrote 100 MB and measured 149,708,800 bytes used before a clean
// detach, but the image the host sealed still mounted as the freshly formatted
// volume: the next job restored it empty (2026-10-21).
func TestCustomAPFSRealWithholdsAnImageMissingTheGuestsWrites(t *testing.T) {
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
	if err := backend.Attach(context.Background(), slot, branch); err != nil {
		t.Fatal(err)
	}
	usage, _ := json.Marshal(map[string]any{"id": slot.ID, "used_bytes": 149_708_800, "capacity_bytes": 19_790_245_888, "changed": true})
	if err := os.WriteFile(filepath.Join(branch, ".usage"), usage, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(branch, ".detached"), []byte(slot.ID), 0644); err != nil {
		t.Fatal(err)
	}
	if err := backend.Seal(slot, branch); cachevolumes.Result(err) != "incomplete" {
		t.Fatal(err)
	}
	if masters, _ := filepath.Glob(filepath.Join(root, "masters", slot.Scope, "*.img")); len(masters) != 0 {
		t.Fatal("published an image without the guest's writes", masters)
	}
}

func TestCustomAPFSReclaimsInterruptedInspection(t *testing.T) {
	image := filepath.Join(t.TempDir(), "cache.sparseimage")
	if err := createCustomImage(context.Background(), image, 20_000_000_000); err != nil {
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

func TestCustomInspectionNeverMountsGuestFilesystem(t *testing.T) {
	for _, fail := range []bool{false, true} {
		var calls []string
		held, err := inspectCustomImage("image", func(_ time.Duration, name string, args ...string) (string, error) {
			call := name + " " + strings.Join(args, " ")
			calls = append(calls, call)
			switch name {
			case "hdiutil":
				if args[0] == "attach" {
					if !strings.Contains(call, "-nomount") || !strings.Contains(call, "-noautofsck") || !strings.Contains(call, "-readonly") {
						t.Fatal(call)
					}
					return "/dev/disk42 \tGUID_partition_scheme \t\n/dev/disk42s1 \tEFI \t\n/dev/disk42s2 \tApple_APFS \t\n/dev/disk43 \tEF57347C-0000-11AA-AA11-0030654\t\n/dev/disk43s1 \t41504653-0000-11AA-AA11-0030654\t\n", nil
				}
				if strings.Join(args, " ") != "detach /dev/disk42 -quiet" {
					t.Fatal(call)
				}
			case "/sbin/fsck_apfs":
				if strings.Join(args, " ") != "-n /dev/rdisk42s2" {
					t.Fatal(call)
				}
				if fail {
					return "", errors.New("corrupt")
				}
			case "diskutil":
				if strings.Join(args, " ") != "apfs list /dev/disk43" {
					t.Fatal(call)
				}
				return "    Size (Capacity Ceiling):      19790245888 B (19.8 GB)\n    Capacity In Use By Volumes:   149708800 B (149.7 MB) (0.8% used)\n", nil
			default:
				t.Fatal(call)
			}
			return "", nil
		})
		if fail && (err == nil || len(calls) != 3) || !fail && (err != nil || held != 149_708_800 || len(calls) != 4) {
			t.Fatal(calls, held, err)
		}
	}
}

func TestCustomAPFSReclaimsInterruptedUnmountedInspection(t *testing.T) {
	image := filepath.Join(t.TempDir(), "cache.sparseimage")
	if err := createCustomImage(context.Background(), image, 20_000_000_000); err != nil {
		t.Fatal(err)
	}
	if _, err := runCmd(time.Minute, "hdiutil", "attach", image, "-readonly", "-nomount", "-noautofsck"); err != nil {
		t.Fatal(err)
	}
	defer detachCustomInspection(image)
	if err := detachCustomInspection(image); err != nil {
		t.Fatal(err)
	}
	out, err := runCmd(time.Minute, "hdiutil", "info")
	if err != nil || strings.Contains(out, image) {
		t.Fatal("inspection device retained", err)
	}
}

func TestCustomAPFSRealKeepsAnUnchangedBranchAsAnEvictedMaster(t *testing.T) {
	root := t.TempDir()
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, MinFreeBytes: 40_000_000_000, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }, Transfer: apfsSmokeTransfer{}}, Create: createCustomImage, Verify: verifyCustomImage}
	if err := backend.Init(); err != nil {
		t.Fatal(err)
	}
	mount := t.TempDir()
	defer runCmd(time.Minute, "hdiutil", "detach", mount, "-force", "-quiet")
	attach := func(path string) {
		t.Helper()
		if _, err := runCmd(time.Minute, "hdiutil", "attach", path, "-owners", "off", "-quiet", "-nobrowse", "-mountpoint", mount); err != nil {
			t.Fatal(err)
		}
	}
	finish := func(slot cachevolumes.Slot, branch string, changed bool) {
		t.Helper()
		if _, err := runCmd(time.Minute, "hdiutil", "detach", mount, "-quiet"); err != nil {
			t.Fatal(err)
		}
		usage, _ := json.Marshal(map[string]any{"id": slot.ID, "used_bytes": 1_000_000, "capacity_bytes": 20_000_000_000, "changed": changed})
		if err := os.WriteFile(filepath.Join(branch, ".usage"), usage, 0644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(branch, ".detached"), []byte(slot.ID), 0644); err != nil {
			t.Fatal(err)
		}
	}
	start := func(slot cachevolumes.Slot) string {
		t.Helper()
		branch := filepath.Join(root, "pods", slot.PodUID, slot.Scope)
		if err := os.MkdirAll(branch, 0755); err != nil {
			t.Fatal(err)
		}
		if err := backend.Attach(context.Background(), slot, branch); err != nil {
			t.Fatal(err)
		}
		if backend.Cold(slot) {
			t.Fatal("started cold")
		}
		attach(filepath.Join(branch, "cache.sparseimage"))
		return branch
	}

	first := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa", Account: 1, Scope: strings.Repeat("a", 64), CanPublish: true, UID: 501}, PodUID: "first"}
	branch := start(first)
	if err := os.WriteFile(filepath.Join(mount, "dependency"), []byte("published"), 0644); err != nil {
		t.Fatal(err)
	}
	finish(first, branch, true)
	if err := backend.Seal(first, branch); err != nil {
		t.Fatal(err)
	}
	masters, _ := filepath.Glob(filepath.Join(root, "masters", first.Scope, "*.img"))
	if len(masters) != 1 {
		t.Fatal(masters)
	}
	saved := first
	saved.BaseGeneration = 1
	saved.ImageDigest = strings.Repeat("b", 40)
	saved.ContentDigest = strings.TrimSuffix(strings.SplitN(filepath.Base(masters[0]), "-", 2)[1], ".img")

	unchanged := saved
	unchanged.ID, unchanged.PodUID = "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb", "second"
	branch = start(unchanged)
	if data, err := os.ReadFile(filepath.Join(mount, "dependency")); err != nil || string(data) != "published" {
		t.Fatal(string(data), err)
	}
	finish(unchanged, branch, false)
	if err := os.Remove(masters[0]); err != nil {
		t.Fatal(err)
	}
	if err := backend.Seal(unchanged, branch); cachevolumes.Result(err) != "unchanged" {
		t.Fatal(err)
	}
	if err := backend.Delete(unchanged, branch); err != nil {
		t.Fatal(err)
	}
	if !backend.HasMaster(saved.Identity) {
		t.Fatal("the host lost its only copy of the saved version")
	}

	next := saved
	next.ID, next.PodUID = "cccccccc-cccc-4ccc-cccc-cccccccccccc", "third"
	start(next)
	if data, err := os.ReadFile(filepath.Join(mount, "dependency")); err != nil || string(data) != "published" {
		t.Fatal(string(data), err)
	}
}
