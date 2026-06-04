package index

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

func newTestIndex(t *testing.T) *BoltIndex {
	t.Helper()
	idx, err := OpenBolt(filepath.Join(t.TempDir(), "index.db"))
	if err != nil {
		t.Fatalf("OpenBolt: %v", err)
	}
	t.Cleanup(func() { _ = idx.Close() })
	return idx
}

func mustPut(t *testing.T, idx *BoltIndex, account uint64, version, scope string, key string, e Entry) {
	t.Helper()
	if err := idx.Put(context.Background(), account, version, scope, []byte(key), e); err != nil {
		t.Fatalf("Put: %v", err)
	}
}

func TestGetExact(t *testing.T) {
	idx := newTestIndex(t)
	mustPut(t, idx, 1, "v2", "refs/heads/main", "Linux-deps", Entry{ObjectID: "obj1", CreatedAt: time.Unix(100, 0)})

	got, ok, err := idx.GetExact(context.Background(), 1, "v2", "refs/heads/main", []byte("Linux-deps"))
	if err != nil || !ok {
		t.Fatalf("GetExact miss: ok=%v err=%v", ok, err)
	}
	if got.ObjectID != "obj1" {
		t.Fatalf("got %q want obj1", got.ObjectID)
	}

	// a different byte key does not match (no normalization).
	if _, ok, _ := idx.GetExact(context.Background(), 1, "v2", "refs/heads/main", []byte("Linux-deps ")); ok {
		t.Fatal("trailing-space key unexpectedly matched")
	}
}

func TestFindByPrefixNewestWins(t *testing.T) {
	idx := newTestIndex(t)
	mustPut(t, idx, 1, "v2", "refs/heads/main", "Linux-deps-old", Entry{ObjectID: "old", CreatedAt: time.Unix(100, 0)})
	mustPut(t, idx, 1, "v2", "refs/heads/main", "Linux-deps-new", Entry{ObjectID: "new", CreatedAt: time.Unix(200, 0)})

	got, ok, err := idx.FindByPrefix(context.Background(), 1, "v2", "refs/heads/main", []byte("Linux-"))
	if err != nil || !ok {
		t.Fatalf("FindByPrefix miss: ok=%v err=%v", ok, err)
	}
	if got.ObjectID != "new" {
		t.Fatalf("newest-wins failed: got %q want new", got.ObjectID)
	}
}

func TestFindByPrefixEmptyMatchesPartition(t *testing.T) {
	idx := newTestIndex(t)
	mustPut(t, idx, 1, "v2", "refs/heads/main", "anything", Entry{ObjectID: "a", CreatedAt: time.Unix(100, 0)})
	if _, ok, _ := idx.FindByPrefix(context.Background(), 1, "v2", "refs/heads/main", []byte("")); !ok {
		t.Fatal("empty prefix should match every key in the partition")
	}
	if _, ok, _ := idx.FindByPrefix(context.Background(), 1, "v2", "refs/heads/other", []byte("")); ok {
		t.Fatal("empty prefix matched outside its scope partition")
	}
}

func TestFindByPrefixSingleChar(t *testing.T) {
	idx := newTestIndex(t)
	mustPut(t, idx, 1, "v2", "refs/heads/main", "Linux-x", Entry{ObjectID: "lx", CreatedAt: time.Unix(100, 0)})
	mustPut(t, idx, 1, "v2", "refs/heads/main", "mac-y", Entry{ObjectID: "my", CreatedAt: time.Unix(100, 0)})

	got, ok, _ := idx.FindByPrefix(context.Background(), 1, "v2", "refs/heads/main", []byte("L"))
	if !ok || got.ObjectID != "lx" {
		t.Fatalf("single-char prefix L: ok=%v got=%q", ok, got.ObjectID)
	}
}

func TestIsolationAcrossTenants(t *testing.T) {
	idx := newTestIndex(t)
	// Same key bytes under two accounts, two scopes, two versions.
	mustPut(t, idx, 1, "v2", "refs/heads/main", "shared-key", Entry{ObjectID: "a1", CreatedAt: time.Unix(100, 0)})
	mustPut(t, idx, 2, "v2", "refs/heads/main", "shared-key", Entry{ObjectID: "a2", CreatedAt: time.Unix(100, 0)})
	mustPut(t, idx, 1, "v3", "refs/heads/main", "shared-key", Entry{ObjectID: "v3", CreatedAt: time.Unix(100, 0)})
	mustPut(t, idx, 1, "v2", "refs/heads/feature", "shared-key", Entry{ObjectID: "feat", CreatedAt: time.Unix(100, 0)})

	checks := []struct {
		account        uint64
		version, scope string
		want           string
	}{
		{1, "v2", "refs/heads/main", "a1"},
		{2, "v2", "refs/heads/main", "a2"},
		{1, "v3", "refs/heads/main", "v3"},
		{1, "v2", "refs/heads/feature", "feat"},
	}
	for _, c := range checks {
		got, ok, _ := idx.GetExact(context.Background(), c.account, c.version, c.scope, []byte("shared-key"))
		if !ok || got.ObjectID != c.want {
			t.Fatalf("isolation breach for (%d,%q,%q): got=%q want=%q", c.account, c.version, c.scope, got.ObjectID, c.want)
		}
		// A prefix scan must also not leak across partitions.
		pg, _, _ := idx.FindByPrefix(context.Background(), c.account, c.version, c.scope, []byte("shared"))
		if pg.ObjectID != c.want {
			t.Fatalf("prefix isolation breach for (%d,%q,%q): got=%q want=%q", c.account, c.version, c.scope, pg.ObjectID, c.want)
		}
	}
}

func TestTraversalKeyIsJustBytes(t *testing.T) {
	idx := newTestIndex(t)
	mustPut(t, idx, 1, "v2", "refs/heads/main", "../../etc/passwd", Entry{ObjectID: "trav", CreatedAt: time.Unix(100, 0)})
	got, ok, _ := idx.GetExact(context.Background(), 1, "v2", "refs/heads/main", []byte("../../etc/passwd"))
	if !ok || got.ObjectID != "trav" {
		t.Fatalf("traversal-looking key not round-tripped as opaque bytes")
	}
	// It must not be reachable from a different account's prefix scan.
	if _, ok, _ := idx.FindByPrefix(context.Background(), 2, "v2", "refs/heads/main", []byte("..")); ok {
		t.Fatal("traversal key leaked into another account")
	}
}
