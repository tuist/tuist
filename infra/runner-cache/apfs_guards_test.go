package cachevolumes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAPFSSealPoisonsABranchWhoseShareImageWasReplaced(t *testing.T) {
	b, remote := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	exposed := filepath.Join(path, "cache.sparseimage")
	if err := os.Remove(exposed); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(exposed, []byte("written elsewhere"), 0600); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)
	if err := b.Seal(slot, path); !errors.Is(err, ErrReplaced) || !errors.Is(err, ErrPoisoned) || Result(err) != "replaced" {
		t.Fatal(err)
	}
	if remote.uploads != 0 {
		t.Fatal("published a branch the guest never wrote to")
	}
}

func TestAPFSSealWithholdsABranchIdenticalToItsBase(t *testing.T) {
	b, remote := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, "cache.sparseimage"), []byte("saved data"), 0600); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)
	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	masters, _ := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if len(masters) != 1 {
		t.Fatal(masters)
	}
	next := slot
	next.ID, next.PodUID = second, "next"
	next.BaseGeneration = 1
	next.ImageDigest = strings.Repeat("b", 40)
	next.ContentDigest = strings.TrimSuffix(strings.SplitN(filepath.Base(masters[0]), "-", 2)[1], ".img")
	nextPath := apfsPath(t, b, next)
	if err := b.Attach(context.Background(), next, nextPath); err != nil {
		t.Fatal(err)
	}
	// The guest reports changes, but none reached the host's image.
	detached(t, nextPath, next.ID)
	uploads := remote.uploads
	if err := b.Seal(next, nextPath); !errors.Is(err, ErrIdentical) || !errors.Is(err, ErrWithheld) || Result(err) != "identical" {
		t.Fatal(err)
	}
	if remote.uploads != uploads {
		t.Fatal("published a branch identical to its base")
	}
	if err := os.WriteFile(filepath.Join(nextPath, "cache.sparseimage"), []byte("new data"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.Seal(next, nextPath); err != nil {
		t.Fatal(err)
	}
	if remote.uploads != uploads+1 {
		t.Fatal("a changed branch was not published")
	}
}
