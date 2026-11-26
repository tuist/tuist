package podagent

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// fakeTart answers requests the way Tart does: it removes each request it
// reads and publishes `<id>.attached`, or `<id>.detached` when release is set.
// It counts the detach requests it read.
func fakeTart(ctx context.Context, dir string, release bool, detaches *atomic.Int32) {
	go func() {
		for ctx.Err() == nil {
			entries, _ := os.ReadDir(dir)
			for _, entry := range entries {
				if id, ok := strings.CutSuffix(entry.Name(), ".attach"); ok {
					_ = os.Remove(filepath.Join(dir, entry.Name()))
					_ = os.WriteFile(filepath.Join(dir, id+".attached"), []byte("{}"), 0600)
				}
				if id, ok := strings.CutSuffix(entry.Name(), ".detach"); ok {
					_ = os.Remove(filepath.Join(dir, entry.Name()))
					detaches.Add(1)
					if release {
						_ = os.WriteFile(filepath.Join(dir, id+".detached"), []byte("{}"), 0600)
					}
				}
			}
			time.Sleep(5 * time.Millisecond)
		}
	}()
}

func TestUSBDisksReleaseOnlyAfterTheGuestsCleanDetach(t *testing.T) {
	for _, release := range []bool{true, false} {
		t.Run(map[bool]string{true: "tart releases", false: "tart never releases"}[release], func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			shares := t.TempDir()
			disks := &USBDisks{Root: t.TempDir(), Shares: shares}
			slot := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "use-1", Scope: strings.Repeat("a", 64)}, PodUID: "pod-1"}
			share := filepath.Join(shares, "pods", slot.PodUID, slot.Scope)
			if err := os.MkdirAll(share, 0755); err != nil {
				t.Fatal(err)
			}
			dir := filepath.Join(disks.Root, "requests", slot.PodUID)
			_ = os.MkdirAll(dir, 0700)
			var detaches atomic.Int32
			fakeTart(ctx, dir, release, &detaches)

			attachCtx, stop := context.WithTimeout(ctx, 5*time.Second)
			defer stop()
			if err := disks.Attach(attachCtx, slot, "/private/volume.img"); err != nil {
				t.Fatal(err)
			}
			if _, err := os.Stat(filepath.Join(share, ".block")); err != nil {
				t.Fatal("the guest is not told its volume is a disk")
			}
			// Without the guest's clean detach the disk stays attached.
			for range 5 {
				disks.Settle()
				time.Sleep(10 * time.Millisecond)
			}
			if detaches.Load() != 0 || disks.Released(slot) {
				t.Fatal("detached before the guest detached cleanly")
			}
			// A marker naming another use does not count either.
			_ = os.WriteFile(filepath.Join(share, ".detached"), []byte("use-2"), 0644)
			disks.Settle()
			time.Sleep(50 * time.Millisecond)
			if detaches.Load() != 0 {
				t.Fatal("detached on another use's marker")
			}
			_ = os.WriteFile(filepath.Join(share, ".detached"), []byte(slot.ID), 0644)
			for range 40 {
				disks.Settle()
				time.Sleep(10 * time.Millisecond)
			}
			if detaches.Load() != 1 {
				t.Fatalf("asked Tart to detach %d times, want once", detaches.Load())
			}
			released, _ := os.ReadFile(filepath.Join(share, ".released"))
			if disks.Released(slot) != release || (string(released) == slot.ID) != release {
				t.Fatalf("released = %v, guest told %q, want %v", disks.Released(slot), released, release)
			}
		})
	}
}

func TestUSBDisksCleanKeepsRequestsOfPodsHoldingVolumes(t *testing.T) {
	disks := &USBDisks{Root: t.TempDir()}
	for _, uid := range []string{"held", "running", "done"} {
		_ = os.MkdirAll(filepath.Join(disks.Root, "requests", uid), 0700)
	}
	slots := []cachevolumes.Slot{{PodUID: "held", State: "active"}, {PodUID: "done", State: "sealed"}}
	if err := disks.Clean(slots, func(uid string) (bool, error) { return uid != "running", nil }); err != nil {
		t.Fatal(err)
	}
	for uid, kept := range map[string]bool{"held": true, "running": true, "done": false} {
		if _, err := os.Stat(filepath.Join(disks.Root, "requests", uid)); (err == nil) != kept {
			t.Errorf("%s kept = %v, want %v", uid, err == nil, kept)
		}
	}
}
