package sandbox

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
)

// objectStore stands in for presigned multipart uploads and downloads.
type objectStore struct {
	mu    sync.Mutex
	parts map[int][]byte
	// gate, when set, holds every part upload until it is closed.
	gate chan struct{}
}

func newObjectStore(t *testing.T) (*objectStore, *httptest.Server) {
	store := &objectStore{parts: map[int][]byte{}}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodPut:
			if store.gate != nil {
				select {
				case <-store.gate:
				case <-r.Context().Done():
					return
				}
			}
			number, _ := strconv.Atoi(r.URL.Query().Get("partNumber"))
			data, _ := io.ReadAll(r.Body)
			store.mu.Lock()
			store.parts[number] = data
			store.mu.Unlock()
			w.Header().Set("ETag", fmt.Sprintf(`"etag-%d"`, number))
		case http.MethodGet:
			w.Write(store.object())
		}
	}))
	t.Cleanup(server.Close)
	return store, server
}

func (s *objectStore) object() []byte {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []byte
	for i := 1; i <= len(s.parts); i++ {
		out = append(out, s.parts[i]...)
	}
	return out
}

func archiveArgs(server *httptest.Server, id string) protocol.ArchiveArgs {
	urls := make([]string, 64)
	for i := range urls {
		urls[i] = fmt.Sprintf("%s/archive?partNumber=%d", server.URL, i+1)
	}
	return protocol.ArchiveArgs{SandboxID: id, PartSize: 1 << 20, PartURLs: urls}
}

func TestArchiveAndRestoreOnAnotherNode(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	store, server := newObjectStore(t)
	h.create(t, "source", 1)
	sourceRoot := vm.RootDir(h.jailBase, "source")
	workspace, err := os.OpenFile(filepath.Join(sourceRoot, "workspace.ext4"), os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := workspace.WriteAt([]byte("uncommitted work"), 300<<20); err != nil {
		t.Fatal(err)
	}
	workspace.Close()

	if _, err := h.m.Archive(ctx, archiveArgs(server, "source")); !errors.Is(err, ErrNotPaused) {
		t.Fatalf("archiving a running sandbox must fail, got %v", err)
	}
	if _, err := h.m.PauseWith(ctx, protocol.PauseArgs{SandboxID: "source", SyncDisks: true}); err != nil {
		t.Fatal(err)
	}
	res, err := h.m.Archive(ctx, archiveArgs(server, "source"))
	if err != nil {
		t.Fatalf("archive: %v", err)
	}
	object := store.object()
	sum := sha256.Sum256(object)
	if res.Bytes != int64(len(object)) || res.SHA256 != hex.EncodeToString(sum[:]) || !res.DisksSynced {
		t.Fatalf("archive result %+v does not describe the object", res)
	}
	if len(res.Parts) == 0 || res.Parts[0].ETag != `"etag-1"` {
		t.Fatalf("parts %+v", res.Parts)
	}
	if res.Bytes > 1<<20 {
		t.Fatalf("a mostly empty 1 GiB workspace archived to %d bytes", res.Bytes)
	}
	if info, _ := h.m.Status(ctx, "source"); info.State != protocol.StatePaused {
		t.Fatalf("archiving must leave the sandbox paused, got %s", info.State)
	}
	if err := h.m.Delete(ctx, "source"); err != nil {
		t.Fatal(err)
	}

	// Another node: nothing of the source on disk, not even the template.
	other := newHarness(t)
	if err := os.RemoveAll(other.tmplDir); err != nil {
		t.Fatal(err)
	}
	source := &protocol.ArchiveSource{URL: server.URL + "/archive", Bytes: res.Bytes, SHA256: res.SHA256}
	if _, err := other.m.Create(ctx, protocol.CreateArgs{SandboxID: "restored", Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 1, FromArchive: source}); err != nil {
		t.Fatalf("restore: %v", err)
	}
	restoredRoot := vm.RootDir(other.jailBase, "restored")
	data, _ := os.ReadFile(filepath.Join(restoredRoot, "workspace.ext4"))
	if len(data) != 1<<30 || string(data[300<<20:300<<20+16]) != "uncommitted work" {
		t.Fatal("the restored workspace must hold what the guest wrote")
	}
	if vm.Exists(filepath.Join(restoredRoot, "mem")) {
		t.Fatal("a restored sandbox has no memory image until its first pause")
	}
	booted := other.launcher.Last()
	for _, call := range booted.Calls() {
		if call.Path == "/snapshot/load" {
			t.Fatal("a restored sandbox must cold boot")
		}
	}
	meta, _ := LoadMetadata(restoredRoot)
	if meta.State != protocol.StateRunning || meta.Tag != "t1" || meta.ID != "restored" {
		t.Fatalf("restored metadata %+v", meta)
	}
	if _, err := other.m.Pause(ctx, "restored"); err != nil {
		t.Fatalf("pause restored: %v", err)
	}

	corrupt := &protocol.ArchiveSource{URL: source.URL, Bytes: source.Bytes, SHA256: strings.Repeat("0", 64)}
	if _, err := other.m.Create(ctx, protocol.CreateArgs{SandboxID: "corrupt", Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 1, FromArchive: corrupt}); err == nil {
		t.Fatal("an archive that fails its checksum must not boot")
	}
	if _, err := other.m.Create(ctx, protocol.CreateArgs{SandboxID: "wrongsize", Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 2, FromArchive: source}); err == nil {
		t.Fatal("a workspace size mismatch must fail")
	}
	for _, id := range []string{"corrupt", "wrongsize"} {
		if vm.Exists(vm.JailDir(other.jailBase, id)) {
			t.Fatalf("a failed restore must remove the jail of %s", id)
		}
	}
	if string(store.object()) != string(object) {
		t.Fatal("a restore must never change the archive")
	}
}

func TestResumeInterruptsAnArchive(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	store, server := newObjectStore(t)
	store.gate = make(chan struct{})
	defer close(store.gate)
	h.create(t, "busy", 1)
	if _, err := h.m.Pause(ctx, "busy"); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := h.m.Archive(ctx, archiveArgs(server, "busy"))
		done <- err
	}()
	for {
		sb, _ := h.m.get("busy")
		sb.mu.Lock()
		started := sb.cancelArchive != nil
		sb.mu.Unlock()
		if started {
			break
		}
	}
	if _, err := h.m.Resume(ctx, "busy"); err != nil {
		t.Fatalf("resume during an archive: %v", err)
	}
	if err := <-done; !errors.Is(err, ErrArchiveInterrupted) {
		t.Fatalf("the archive must report the interruption, got %v", err)
	}
}
