package objstore

import (
	"bytes"
	"context"
	"io"
	"testing"
)

func TestFakePutGetRoundTrip(t *testing.T) {
	f := NewFake()
	ctx := context.Background()
	want := []byte("hello world")
	if err := f.PutObject(ctx, "k", bytes.NewReader(want), int64(len(want))); err != nil {
		t.Fatal(err)
	}
	rc, info, err := f.GetObjectRange(ctx, "k", 0, -1)
	if err != nil {
		t.Fatal(err)
	}
	defer rc.Close()
	got, _ := io.ReadAll(rc)
	if !bytes.Equal(got, want) {
		t.Fatalf("got %q want %q", got, want)
	}
	if info.Size != int64(len(want)) {
		t.Fatalf("size %d want %d", info.Size, len(want))
	}
}

func TestFakeRangeRead(t *testing.T) {
	f := NewFake()
	ctx := context.Background()
	data := []byte("0123456789")
	_ = f.PutObject(ctx, "k", bytes.NewReader(data), int64(len(data)))

	rc, _, err := f.GetObjectRange(ctx, "k", 2, 3)
	if err != nil {
		t.Fatal(err)
	}
	defer rc.Close()
	got, _ := io.ReadAll(rc)
	if string(got) != "234" {
		t.Fatalf("range got %q want 234", got)
	}
}

func TestFakeMultipartEnforcesMinPart(t *testing.T) {
	f := NewFake()
	ctx := context.Background()
	id, _ := f.CreateMultipart(ctx, "k")
	small := bytes.Repeat([]byte("a"), 1<<20) // 1 MiB
	big := bytes.Repeat([]byte("b"), MinPartSize)
	e1, _ := f.UploadPart(ctx, "k", id, 1, bytes.NewReader(small), int64(len(small)))
	e2, _ := f.UploadPart(ctx, "k", id, 2, bytes.NewReader(big), int64(len(big)))

	// part 1 (non-last) is below the minimum: complete must fail.
	err := f.CompleteMultipart(ctx, "k", id, []CompletedPart{{1, e1}, {2, e2}})
	if err == nil {
		t.Fatal("CompleteMultipart accepted a sub-5MiB non-final part")
	}
}

func TestFakeMultipartHappyPath(t *testing.T) {
	f := NewFake()
	ctx := context.Background()
	id, _ := f.CreateMultipart(ctx, "k")
	p1 := bytes.Repeat([]byte("a"), MinPartSize)
	p2 := bytes.Repeat([]byte("b"), 1<<20) // last part may be < 5MiB
	e1, _ := f.UploadPart(ctx, "k", id, 1, bytes.NewReader(p1), int64(len(p1)))
	e2, _ := f.UploadPart(ctx, "k", id, 2, bytes.NewReader(p2), int64(len(p2)))

	if err := f.CompleteMultipart(ctx, "k", id, []CompletedPart{{1, e1}, {2, e2}}); err != nil {
		t.Fatalf("CompleteMultipart: %v", err)
	}
	got, ok := f.ObjectBytes("k")
	if !ok {
		t.Fatal("object missing after complete")
	}
	if len(got) != len(p1)+len(p2) {
		t.Fatalf("assembled size %d want %d", len(got), len(p1)+len(p2))
	}
	if f.OpenUploads() != 0 {
		t.Fatal("upload not cleaned up after complete")
	}
}

func TestFakeAbortClearsUpload(t *testing.T) {
	f := NewFake()
	ctx := context.Background()
	id, _ := f.CreateMultipart(ctx, "k")
	if f.OpenUploads() != 1 {
		t.Fatal("expected one open upload")
	}
	_ = f.AbortMultipart(ctx, "k", id)
	if f.OpenUploads() != 0 {
		t.Fatal("abort did not clear the upload")
	}
}
