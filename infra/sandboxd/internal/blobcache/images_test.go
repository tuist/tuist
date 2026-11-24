package blobcache

import (
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"
)

// treeRecorder stands in for mkfs.ext4: it records the tree an image would
// hold, file names to contents and modes, by image path.
type treeRecorder struct {
	mu    sync.Mutex
	trees map[string]map[string]string
	modes map[string]fs.FileMode
}

func (r *treeRecorder) mkfs(_ context.Context, image, root string) error {
	tree := map[string]string{}
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || p == root {
			return err
		}
		rel, _ := filepath.Rel(root, p)
		info, err := d.Info()
		if err != nil {
			return err
		}
		r.mu.Lock()
		r.modes[rel] = info.Mode()
		r.mu.Unlock()
		if !d.IsDir() {
			b, err := os.ReadFile(p)
			if err != nil {
				return err
			}
			tree[rel] = string(b)
		}
		return nil
	})
	r.mu.Lock()
	r.trees[image] = tree
	r.mu.Unlock()
	return err
}

func waitImage(t *testing.T, c *Cache, s Scope, bytes int64) string {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if p, ok := c.Image(s, bytes); ok {
			return p
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("no inputs image was built")
	return ""
}

func TestInputsImageHoldsOnlyTheScopesRepeatedBlobsReadOnly(t *testing.T) {
	c, cas, endpoint := setup(t, 1<<20)
	rec := &treeRecorder{trees: map[string]map[string]string{}, modes: map[string]fs.FileMode{}}
	c.Mkfs = rec.mkfs
	a := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}
	b := Scope{Endpoint: endpoint, Instance: "b", Token: "token-b"}
	hot, hotSize := cas.put("toolchain library")
	once, onceSize := cas.put("read by one action")
	other, otherSize := cas.put("other project's library")
	for _, r := range []struct {
		s    Scope
		hash string
		size int64
	}{{a, hot, hotSize}, {a, hot, hotSize}, {a, once, onceSize}, {b, other, otherSize}, {b, other, otherSize}} {
		if _, err := readAll(t, c, r.s, r.hash, r.size); err != nil {
			t.Fatal(err)
		}
	}
	const workspace = 64 << 20
	imageA := waitImage(t, c, a, workspace)
	imageB := waitImage(t, c, b, workspace)
	rec.mu.Lock()
	defer rec.mu.Unlock()
	name := func(hash string, size int64) string {
		return filepath.Join(InputsDir, hash+"-"+itoa(size))
	}
	if got := rec.trees[imageA]; len(got) != 1 || got[name(hot, hotSize)] != "toolchain library" {
		t.Fatalf("scope a's image holds %v, want only its repeated blob", got)
	}
	if got := rec.trees[imageB]; len(got) != 1 || got[name(other, otherSize)] != "other project's library" {
		t.Fatalf("scope b's image holds %v, want only its own blob", got)
	}
	if m := rec.modes[InputsDir]; !m.IsDir() || m.Perm() != 0o700 {
		t.Fatalf("inputs directory mode %v, want root's alone", m)
	}
	if m := rec.modes[name(hot, hotSize)]; m.Perm() != 0o444 {
		t.Fatalf("blob mode %v, want read-only", m)
	}
	// An image is only handed out for the workspace size it was built for.
	if _, ok := c.Image(a, workspace*2); ok {
		t.Fatal("image handed out for another workspace size")
	}
}

func TestBlobFillDropsTheInputsImageWhenNoBlobIsLeftToEvict(t *testing.T) {
	const budget = 256 << 10
	c, cas, endpoint := setup(t, budget)
	// The image takes most of the budget on disk.
	c.Mkfs = func(_ context.Context, image, _ string) error {
		return os.WriteFile(image, make([]byte, 192<<10), 0o600)
	}
	s := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}
	hot, hotSize := cas.put("toolchain library")
	for range 2 {
		if _, err := readAll(t, c, s, hot, hotSize); err != nil {
			t.Fatal(err)
		}
	}
	image := waitImage(t, c, s, 1<<20)
	large := string(make([]byte, 128<<10))
	hash, size := cas.put(large)
	got, err := readAll(t, c, s, hash, size)
	if err != nil {
		t.Fatalf("blob that fits once the image is gone: %v", err)
	}
	if got != large {
		t.Fatal("blob content differs")
	}
	if _, ok := c.Image(s, 1<<20); ok {
		t.Fatal("image still handed out after it was dropped for a blob")
	}
	if _, err := os.Stat(image); !os.IsNotExist(err) {
		t.Fatalf("dropped image still on disk: %v", err)
	}
}

func itoa(n int64) string { return strconv.FormatInt(n, 10) }
