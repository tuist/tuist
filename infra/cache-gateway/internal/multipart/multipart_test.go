package multipart

import (
	"bytes"
	"context"
	"fmt"
	"testing"

	"github.com/tuist/tuist/infra/cache-gateway/internal/objstore"
)

func block(n int, fill byte) []byte { return bytes.Repeat([]byte{fill}, n) }

func TestSmallBlocksCoalesceIntoValidParts(t *testing.T) {
	store := objstore.NewFake()
	m := New(store)
	ctx := context.Background()
	key := "acct/1/blob/x"

	// 20 blocks of 1 MiB each = 20 MiB total, well above the floor but
	// each block is below the 5 MiB minimum part size.
	var ids []string
	var want bytes.Buffer
	for i := 0; i < 20; i++ {
		id := fmt.Sprintf("b%02d", i)
		data := block(1<<20, byte('A'+i))
		if err := m.PutBlock(ctx, key, id, data); err != nil {
			t.Fatal(err)
		}
		ids = append(ids, id)
		want.Write(data)
	}
	if err := m.PutBlockList(ctx, key, ids); err != nil {
		t.Fatalf("PutBlockList: %v", err)
	}
	got, ok := store.ObjectBytes(key)
	if !ok {
		t.Fatal("object not written")
	}
	if !bytes.Equal(got, want.Bytes()) {
		t.Fatalf("assembled bytes differ: got %d want %d", len(got), want.Len())
	}
	if store.OpenUploads() != 0 {
		t.Fatal("multipart upload left open")
	}
}

func TestSubFloorTotalIsSingleShot(t *testing.T) {
	store := objstore.NewFake()
	m := New(store)
	ctx := context.Background()
	key := "acct/1/blob/small"

	// Single 3 MiB block: below the multipart floor entirely.
	data := block(3<<20, 'z')
	_ = m.PutBlock(ctx, key, "only", data)
	if err := m.PutBlockList(ctx, key, []string{"only"}); err != nil {
		t.Fatalf("PutBlockList: %v", err)
	}
	got, ok := store.ObjectBytes(key)
	if !ok || !bytes.Equal(got, data) {
		t.Fatal("single-shot object incorrect")
	}
	if store.OpenUploads() != 0 {
		t.Fatal("a multipart upload was created for a sub-floor object")
	}
}

func TestBlockListOrderDeterminesBytes(t *testing.T) {
	store := objstore.NewFake()
	m := New(store)
	ctx := context.Background()
	key := "acct/1/blob/ordered"

	// Stage in one order, commit in the reverse order. Each block is
	// >= 5 MiB so they become distinct parts; the final object must be
	// the list-ordered concatenation, not the staging order.
	a := block(objstore.MinPartSize, 'a')
	b := block(objstore.MinPartSize, 'b')
	c := block(1<<20, 'c') // final, may be small
	_ = m.PutBlock(ctx, key, "a", a)
	_ = m.PutBlock(ctx, key, "b", b)
	_ = m.PutBlock(ctx, key, "c", c)

	if err := m.PutBlockList(ctx, key, []string{"b", "a", "c"}); err != nil {
		t.Fatalf("PutBlockList: %v", err)
	}
	want := append(append(append([]byte(nil), b...), a...), c...)
	got, _ := store.ObjectBytes(key)
	if !bytes.Equal(got, want) {
		t.Fatal("final bytes do not follow block-list order")
	}
}

func TestUnknownBlockAborts(t *testing.T) {
	store := objstore.NewFake()
	m := New(store)
	ctx := context.Background()
	key := "acct/1/blob/bad"

	_ = m.PutBlock(ctx, key, "real", block(1<<20, 'a'))
	err := m.PutBlockList(ctx, key, []string{"real", "ghost"})
	if err == nil {
		t.Fatal("PutBlockList accepted an unknown block id")
	}
	if store.OpenUploads() != 0 {
		t.Fatal("a failed commit left an open upload")
	}
	if _, ok := store.ObjectBytes(key); ok {
		t.Fatal("a failed commit wrote a partial object")
	}
}

func TestConcurrentObjectsAreIndependent(t *testing.T) {
	store := objstore.NewFake()
	m := New(store)
	ctx := context.Background()

	done := make(chan error, 2)
	upload := func(key string, fill byte) {
		var ids []string
		for i := 0; i < 6; i++ {
			id := fmt.Sprintf("%s-%d", key, i)
			_ = m.PutBlock(ctx, key, id, block(1<<20, fill))
			ids = append(ids, id)
		}
		done <- m.PutBlockList(ctx, key, ids)
	}
	go upload("acct/1/blob/p", 'p')
	go upload("acct/1/blob/q", 'q')
	for i := 0; i < 2; i++ {
		if err := <-done; err != nil {
			t.Fatalf("concurrent upload failed: %v", err)
		}
	}
	p, _ := store.ObjectBytes("acct/1/blob/p")
	q, _ := store.ObjectBytes("acct/1/blob/q")
	if !bytes.Equal(p, block(6<<20, 'p')) || !bytes.Equal(q, block(6<<20, 'q')) {
		t.Fatal("concurrent uploads cross-contaminated")
	}
}
