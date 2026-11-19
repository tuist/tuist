package macosandbox

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/archive"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// Only an evicted sandbox whose guest flushed its disks moves: a running or
// resident one still writes to its disk, and an unflushed one holds writes
// only its checkpoint has. A resume meanwhile interrupts the upload.
func TestArchiveTakesOnlyAnEvictedFlushedSandboxAndAResumeInterruptsIt(t *testing.T) {
	m, r, _, a := harness(t)
	m.Grace = time.Nanosecond
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Archive(ctx, protocol.ArchiveArgs{SandboxID: a.SandboxID}); !errors.Is(err, ErrNotArchivable) {
		t.Fatalf("archived a running sandbox: %v", err)
	}
	if err := m.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Archive(ctx, protocol.ArchiveArgs{SandboxID: a.SandboxID}); !errors.Is(err, ErrNotArchivable) {
		t.Fatalf("archived a resident sandbox: %v", err)
	}
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if res, err := m.Archive(ctx, protocol.ArchiveArgs{SandboxID: a.SandboxID}); err != nil || res.Bytes != 1 {
		t.Fatalf("archive of an evicted sandbox: %+v %v", res, err)
	}

	// Resumed, it runs on its disk again; evicted unflushed, it stays.
	if err := m.Resume(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	r.unflushed = true
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Archive(ctx, protocol.ArchiveArgs{SandboxID: a.SandboxID}); !errors.Is(err, ErrNotArchivable) {
		t.Fatalf("archived an unflushed sandbox: %v", err)
	}

	r.unflushed = false
	if err := m.Resume(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	r.archiveStarted = make(chan struct{})
	done := make(chan error, 1)
	go func() {
		_, err := m.Archive(ctx, protocol.ArchiveArgs{SandboxID: a.SandboxID})
		done <- err
	}()
	<-r.archiveStarted
	if err := m.Resume(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if err := <-done; !errors.Is(err, ErrArchiveInterrupted) {
		t.Fatalf("resume did not interrupt the archive: %v", err)
	}
}

// The archive is the VM's own files, the overlay sparse, under the header a
// restore checks, uploaded through the presigned part URLs.
func TestArchiveUploadsTheStackedVMFiles(t *testing.T) {
	var mu sync.Mutex
	parts := map[int][]byte{}
	store := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		var n int
		fmt.Sscanf(req.URL.Query().Get("part"), "%d", &n)
		body, _ := io.ReadAll(req.Body)
		mu.Lock()
		parts[n] = body
		mu.Unlock()
		w.Header().Set("ETag", fmt.Sprintf(`"%d"`, n))
	}))
	defer store.Close()

	home := t.TempDir()
	r := &Record{CreateArgs: protocol.CreateArgs{SandboxID: "6f0b2c1e-6d55-4bb8-9a59-0b5d5f9f3a10", Template: "macos", TemplateTag: "ghcr.io/tuist/runner@sha256:abc", WorkspaceGB: 10}}
	runtime := &TartRuntime{Client: &tart.Client{HomeDir: home}}
	dir := runtime.directory(r)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	written := []byte("written by the session")
	overlay, err := os.Create(filepath.Join(dir, "overlay.asif"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := overlay.WriteAt(written, 3<<30); err != nil {
		t.Fatal(err)
	}
	overlay.Truncate(8 << 30)
	overlay.Close()
	for name, data := range map[string]string{"config.json": `{"cpuCount":8}`, "nvram.bin": "nvram", "manifest.json": "{}", "state.vzvmsave": "checkpoint"} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(data), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	urls := []string{store.URL + "/?part=1", store.URL + "/?part=2"}
	res, err := runtime.Archive(context.Background(), r, protocol.ArchiveArgs{SandboxID: r.SandboxID, PartSize: 5 << 20, PartURLs: urls})
	if err != nil {
		t.Fatal(err)
	}
	var object bytes.Buffer
	for i := range res.Parts {
		object.Write(parts[res.Parts[i].PartNumber])
	}
	if int64(object.Len()) != res.Bytes {
		t.Fatalf("uploaded %d bytes, reported %d", object.Len(), res.Bytes)
	}
	restored := t.TempDir()
	header, err := archive.Extract(&object, restored, map[string]int64{"config.json": 1 << 20, "nvram.bin": 1 << 20, "overlay.asif": 8 << 30})
	if err != nil {
		t.Fatal(err)
	}
	if header.Tag != r.TemplateTag || header.WorkspaceGB != 10 || !header.DisksSynced || header.SourceSandbox != r.SandboxID {
		t.Fatalf("header: %+v", header)
	}
	got := make([]byte, len(written))
	f, err := os.Open(filepath.Join(restored, "overlay.asif"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err := f.ReadAt(got, 3<<30); err != nil || !bytes.Equal(got, written) {
		t.Fatalf("overlay content: %q %v", got, err)
	}
	if info, _ := f.Stat(); info.Size() != 8<<30 {
		t.Fatalf("overlay size %d", info.Size())
	}
	if res.StoredBytes > 2<<20 {
		t.Fatalf("stored %d bytes of a sparse overlay", res.StoredBytes)
	}
	if config, _ := os.ReadFile(filepath.Join(restored, "config.json")); !strings.Contains(string(config), "cpuCount") {
		t.Fatalf("config: %q", config)
	}
}

func TestRestoreImage(t *testing.T) {
	const repo = "ghcr.io/tuist/runner-image"
	old := repo + "@sha256:" + strings.Repeat("a", 64)
	current := repo + "@sha256:" + strings.Repeat("b", 64)
	for _, tc := range []struct {
		name, current, archived, want string
	}{
		{"same image", current, current, current},
		{"older digest of the repository", current, old, old},
		{"current image named by tag", repo + ":macos-26-6-0.59.0-stacked", old, old},
		{"registry with a port", "rack:5000/runner-image@sha256:" + strings.Repeat("b", 64), "rack:5000/runner-image@sha256:" + strings.Repeat("a", 64), "rack:5000/runner-image@sha256:" + strings.Repeat("a", 64)},
		{"no recorded image", current, "", current},
	} {
		got, err := restoreImage(tc.current, tc.archived)
		if err != nil || got != tc.want {
			t.Errorf("%s: restoreImage(%q, %q) = %q, %v; want %q", tc.name, tc.current, tc.archived, got, err, tc.want)
		}
	}
	for _, archived := range []string{
		repo + ":macos-26-6-0.58.0-stacked",                           // a tag can move
		"ghcr.io/evil/runner-image@sha256:" + strings.Repeat("a", 64), // another repository
		"ghcr.io/tuist/runner-image-x@sha256:" + strings.Repeat("a", 64),
		repo + "@sha256:abc", // not a digest
	} {
		if _, err := restoreImage(current, archived); !errors.Is(err, ErrArchiveMismatch) {
			t.Errorf("restoreImage(%q) = %v, want ErrArchiveMismatch", archived, err)
		}
	}
}
