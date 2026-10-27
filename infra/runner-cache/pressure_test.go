package cachevolumes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// relievedMasters writes one master per scope, oldest first, on a filesystem
// whose free space grows by 10 bytes for every master removed.
func relievedMasters(t *testing.T, scopes ...string) (*LocalImages, func(string) string) {
	t.Helper()
	b, _ := newLocal(t)
	master := func(scope string) string { return filepath.Join(b.Root, "masters", scope, "1.img") }
	for i, scope := range scopes {
		if err := os.MkdirAll(filepath.Dir(master(scope)), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(master(scope), []byte("master"), 0600); err != nil {
			t.Fatal(err)
		}
		modified := time.Now().Add(time.Duration(i-len(scopes)) * time.Hour)
		if err := os.Chtimes(master(scope), modified, modified); err != nil {
			t.Fatal(err)
		}
	}
	b.FreeBytes = func(string) (uint64, error) {
		remaining, _ := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
		return uint64(10 * (len(scopes) - len(remaining))), nil
	}
	return b, master
}

func TestRelieveEvictsIdleMastersOldestFirstUntilFree(t *testing.T) {
	held, oldest, newer, newest := strings.Repeat("a", 64), strings.Repeat("b", 64), strings.Repeat("c", 64), strings.Repeat("d", 64)
	b, master := relievedMasters(t, held, oldest, newer, newest)

	b.InUse = func(scope string) bool { return scope == held }
	evicted, err := b.Relieve(context.Background(), 20)
	if err != nil {
		t.Fatal(err)
	}

	if evicted != 2 {
		t.Fatalf("evicted %d masters, want the two oldest idle ones", evicted)
	}
	for scope, kept := range map[string]bool{held: true, oldest: false, newer: false, newest: true} {
		if _, err := os.Stat(master(scope)); (err == nil) != kept {
			t.Errorf("master %s kept=%v, want %v", scope[:1], err == nil, kept)
		}
	}
}

func TestRelieveLeavesMastersAloneWithRoom(t *testing.T) {
	b, master := relievedMasters(t, strings.Repeat("a", 64))
	b.FreeBytes = func(string) (uint64, error) { return 1, nil }

	if evicted, err := b.Relieve(context.Background(), 1); err != nil || evicted != 0 {
		t.Fatalf("evicted %d masters with room: %v", evicted, err)
	}
	if _, err := os.Stat(master(strings.Repeat("a", 64))); err != nil {
		t.Fatal(err)
	}
}

func TestAPFSWithholdsABranchWrittenUnderPressure(t *testing.T) {
	b, _ := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = 1, strings.Repeat("b", 40), strings.Repeat("c", 64)
	master := b.master(slot)
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, []byte("saved APFS"), 0600); err != nil {
		t.Fatal(err)
	}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}

	if err := b.MarkPressure(slot); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)

	if err := b.Seal(slot, path); !errors.Is(err, ErrPressure) || !errors.Is(err, ErrWithheld) || Result(err) != "pressure" {
		t.Fatalf("sealed a branch written under pressure: %v", err)
	}
	if err := b.Delete(slot, path); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(b.image(slot) + ".pressure"); !os.IsNotExist(err) {
		t.Fatal("left the pressure marker behind", err)
	}
}

func TestAPFSPressureNeverMarksASlotWithoutABranch(t *testing.T) {
	b, _ := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}

	if err := b.MarkPressure(slot); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(b.image(slot) + ".pressure"); !os.IsNotExist(err) {
		t.Fatal("marked a slot that has written nothing", err)
	}
}
