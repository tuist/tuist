package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// evictMaster removes the slot's base master the way admission does while the
// job still runs.
func evictMaster(t *testing.T, b *LocalImages, slot Slot) {
	t.Helper()
	if err := removeMaster(b.master(slot)); err != nil {
		t.Fatal(err)
	}
}

func TestAPFSKeepsAnUnchangedBranchAsTheMasterEvictedWhileTheJobRan(t *testing.T) {
	b, remote, slot, path := finishedClone(t, map[string]any{"used_bytes": 3, "capacity_bytes": 20_000_000_000, "changed": false})
	evictMaster(t, &b.LocalImages, slot)
	if err := os.WriteFile(b.image(slot), []byte("branch"), 0600); err != nil {
		t.Fatal(err)
	}

	if err := b.Seal(slot, path); Result(err) != "unchanged" {
		t.Fatal("published an unchanged volume:", err)
	}
	if err := b.Delete(slot, path); err != nil {
		t.Fatal(err)
	}

	if data, _ := os.ReadFile(b.master(slot)); string(data) != "branch" {
		t.Fatalf("master holds %q; the host lost its only copy of the saved version", data)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded an unchanged volume")
	}
	next := Slot{Identity: slot.Identity, PodUID: "next"}
	next.ID = third
	if err := b.Attach(context.Background(), next, apfsPath(t, b, next)); err != nil {
		t.Fatal(err)
	}
	if b.Cold(next) || remote.downloads != 0 {
		t.Fatal("the next job on this host started cold")
	}
}

func TestAPFSKeepsTheMasterAnUnchangedBranchWasClonedFrom(t *testing.T) {
	b, _, slot, path := finishedClone(t, map[string]any{"used_bytes": 3, "capacity_bytes": 20_000_000_000, "changed": false})
	if err := os.WriteFile(b.image(slot), []byte("branch"), 0600); err != nil {
		t.Fatal(err)
	}
	verified := false
	b.Verify = func(string) error { verified = true; return nil }

	if err := b.Seal(slot, path); Result(err) != "unchanged" {
		t.Fatal(err)
	}

	if data, _ := os.ReadFile(b.master(slot)); string(data) != "stale" {
		t.Fatalf("replaced the installed master with the branch: %q", data)
	}
	if verified {
		t.Fatal("verified a branch the host does not need")
	}
}

func TestAPFSNeverKeepsAnUnchangedBranchOfAnOlderGeneration(t *testing.T) {
	b, _ := newAPFS(t)
	installMaster(t, &b.LocalImages, second, strings.Repeat("a", 64), 1, time.Now())
	slot := warmSlot(first, "pod")
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(2).BaseGeneration, head(2).ImageDigest, head(2).ContentDigest
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	detachWithUsage(t, slot, path, map[string]any{"used_bytes": 3, "capacity_bytes": 20_000_000_000, "changed": false})

	if err := b.Seal(slot, path); Result(err) != "unchanged" {
		t.Fatal(err)
	}

	if b.HasMaster(slot.Identity) {
		t.Fatal("installed generation 1's content as generation 2")
	}
}

func TestAPFSNeverKeepsAnUnchangedBranchThatFailsVerification(t *testing.T) {
	b, _, slot, path := finishedClone(t, map[string]any{"used_bytes": 3, "capacity_bytes": 20_000_000_000, "changed": false})
	evictMaster(t, &b.LocalImages, slot)
	b.Verify = func(string) error { return errors.New("fsck failed") }

	if err := b.Seal(slot, path); Result(err) != "unchanged" {
		t.Fatal(err)
	}

	if b.HasMaster(slot.Identity) {
		t.Fatal("installed a branch that failed verification as a master")
	}
}

func TestLocalKeepsAnUnchangedBranchAsTheMasterEvictedWhileTheJobRan(t *testing.T) {
	b, remote := newLocal(t)
	saved := installMaster(t, b, second, strings.Repeat("a", 64), 1, time.Now())
	slot := Slot{Identity: saved.Identity, PodUID: "p"}
	slot.ID = first
	path := t.TempDir()
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	afterMarker(t, path)
	evictMaster(t, b, slot)

	if err := b.Seal(slot, path); !errors.Is(err, ErrUnchanged) {
		t.Fatal("published an unchanged volume:", err)
	}

	if !b.HasMaster(slot.Identity) {
		t.Fatal("the host lost its only copy of the saved version")
	}
	if err := b.Seal(slot, path); !errors.Is(err, ErrUnchanged) {
		t.Fatal("a retried seal of the kept branch did not withhold it:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded an unchanged volume")
	}
}

func detachWithUsage(t *testing.T, slot Slot, path string, usage map[string]any) {
	t.Helper()
	usage["id"] = slot.ID
	data, _ := json.Marshal(usage)
	if err := os.WriteFile(filepath.Join(path, ".usage"), data, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, ".detached"), []byte(slot.ID), 0644); err != nil {
		t.Fatal(err)
	}
}
