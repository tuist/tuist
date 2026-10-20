package cachevolumes

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"
)

// objectServer serves an image archive the way object storage does, through a
// handler the test can make misbehave per request.
type objectServer struct {
	*httptest.Server
	archive []byte
	slot    Slot

	mu        sync.Mutex
	ranges    []string
	links     int
	misbehave func(attempt int, w http.ResponseWriter, r *http.Request) bool
}

func newObjectServer(t *testing.T) *objectServer {
	t.Helper()
	dir := t.TempDir()
	image := make([]byte, 4<<20)
	if _, err := rand.Read(image); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "image"), image, 0600); err != nil {
		t.Fatal(err)
	}
	_, digest, err := compressImage(filepath.Join(dir, "image"), filepath.Join(dir, "image.zst"))
	if err != nil {
		t.Fatal(err)
	}
	archive, err := os.ReadFile(filepath.Join(dir, "image.zst"))
	if err != nil {
		t.Fatal(err)
	}
	s := &objectServer{archive: archive, slot: Slot{Identity: identity(first)}}
	s.slot.BaseGeneration, s.slot.ContentDigest = 1, digest
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			s.mu.Lock()
			s.links++
			s.mu.Unlock()
			json.NewEncoder(w).Encode(map[string]any{"generation": 1, "download_url": s.URL + "/object"})
			return
		}
		s.mu.Lock()
		s.ranges = append(s.ranges, r.Header.Get("Range"))
		attempt, misbehave := len(s.ranges), s.misbehave
		s.mu.Unlock()
		if misbehave != nil && misbehave(attempt, w, r) {
			return
		}
		http.ServeContent(w, r, "object", time.Time{}, bytes.NewReader(s.archive))
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *objectServer) transfer() *HTTPTransfer {
	return &HTTPTransfer{
		URL: s.URL, Node: "node", Client: s.Client(), DownloadClient: s.Client(), MaxBytes: 8 << 20,
		Token:        func(context.Context) (string, error) { return "token", nil },
		stallTimeout: 200 * time.Millisecond, retryBackoff: time.Millisecond,
	}
}

func (s *objectServer) requestedRanges() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.ranges...)
}

// sendHalf writes the first half of the archive and returns, cutting the
// response short of its declared length.
func (s *objectServer) sendHalf(w http.ResponseWriter) {
	w.Header().Set("Content-Length", strconv.Itoa(len(s.archive)))
	w.WriteHeader(http.StatusOK)
	w.Write(s.archive[:len(s.archive)/2])
	w.(http.Flusher).Flush()
	panic(http.ErrAbortHandler)
}

func restored(t *testing.T, path string) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil || info.Size() != 4<<20 {
		t.Fatal("the image was not restored:", err)
	}
	if exists(path + ".part") {
		t.Fatal("left the downloaded archive behind")
	}
}

func TestDownloadResumesWhereAnInterruptedTransferStopped(t *testing.T) {
	s := newObjectServer(t)
	s.misbehave = func(attempt int, w http.ResponseWriter, _ *http.Request) bool {
		if attempt == 1 {
			s.sendHalf(w)
		}
		return false
	}
	path := filepath.Join(t.TempDir(), "image")

	if err := s.transfer().Download(context.Background(), s.slot, path); err != nil {
		t.Fatal(err)
	}

	restored(t, path)
	ranges := s.requestedRanges()
	if len(ranges) != 2 || ranges[0] != "" || ranges[1] != "bytes="+strconv.Itoa(len(s.archive)/2)+"-" {
		t.Fatalf("requested ranges %q; the retry did not resume", ranges)
	}
	s.mu.Lock()
	links := s.links
	s.mu.Unlock()
	if links != 2 {
		t.Fatalf("asked for %d download links; every attempt needs a fresh one", links)
	}
}

func TestDownloadAbandonsAStalledTransferAndResumes(t *testing.T) {
	s := newObjectServer(t)
	s.misbehave = func(attempt int, w http.ResponseWriter, r *http.Request) bool {
		if attempt != 1 {
			return false
		}
		w.Header().Set("Content-Length", strconv.Itoa(len(s.archive)))
		w.WriteHeader(http.StatusOK)
		w.Write(s.archive[:len(s.archive)/2])
		w.(http.Flusher).Flush()
		<-r.Context().Done()
		return true
	}
	path := filepath.Join(t.TempDir(), "image")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := s.transfer().Download(ctx, s.slot, path); err != nil {
		t.Fatal("a stalled transfer was not abandoned:", err)
	}

	restored(t, path)
	if ranges := s.requestedRanges(); len(ranges) != 2 || ranges[1] == "" {
		t.Fatalf("requested ranges %q", ranges)
	}
}

func TestDownloadKeepsProgressForTheNextCall(t *testing.T) {
	s := newObjectServer(t)
	failing := true
	s.misbehave = func(_ int, w http.ResponseWriter, _ *http.Request) bool {
		if failing {
			s.sendHalf(w)
		}
		return false
	}
	path := filepath.Join(t.TempDir(), "image")
	transfer := s.transfer()
	if err := transfer.Download(context.Background(), s.slot, path); err == nil {
		t.Fatal("every attempt failed but the download succeeded")
	}
	if exists(path) {
		t.Fatal("restored an incomplete archive")
	}

	failing = false
	if err := transfer.Download(context.Background(), s.slot, path); err != nil {
		t.Fatal(err)
	}

	restored(t, path)
	ranges := s.requestedRanges()
	if last := ranges[len(ranges)-1]; last != "bytes="+strconv.Itoa(len(s.archive)/2)+"-" {
		t.Fatalf("the next call requested %q instead of resuming", last)
	}
}

func TestDownloadRestoresAnArchiveThatWasAlreadyComplete(t *testing.T) {
	s := newObjectServer(t)
	path := filepath.Join(t.TempDir(), "image")
	if err := os.WriteFile(path+".part", s.archive, 0600); err != nil {
		t.Fatal(err)
	}

	if err := s.transfer().Download(context.Background(), s.slot, path); err != nil {
		t.Fatal(err)
	}

	restored(t, path)
}

func TestDownloadStartsOverWhenTheServerIgnoresTheRange(t *testing.T) {
	s := newObjectServer(t)
	s.misbehave = func(attempt int, w http.ResponseWriter, r *http.Request) bool {
		if attempt == 1 {
			s.sendHalf(w)
		}
		r.Header.Del("Range")
		return false
	}
	path := filepath.Join(t.TempDir(), "image")

	if err := s.transfer().Download(context.Background(), s.slot, path); err != nil {
		t.Fatal(err)
	}

	restored(t, path)
}

func TestDownloadDiscardsAnArchiveThatDoesNotMatchTheSavedVersion(t *testing.T) {
	s := newObjectServer(t)
	path := filepath.Join(t.TempDir(), "image")
	corrupt := append([]byte(nil), s.archive...)
	corrupt[len(corrupt)/2] ^= 0xff
	if err := os.WriteFile(path+".part", corrupt, 0600); err != nil {
		t.Fatal(err)
	}

	if err := s.transfer().Download(context.Background(), s.slot, path); err == nil {
		t.Fatal("restored an archive that does not match the saved version")
	}

	if exists(path+".part") || exists(path) {
		t.Fatal("kept a corrupt archive to resume from")
	}
}

func TestDownloadDoesNotRetryARefusedLink(t *testing.T) {
	s := newObjectServer(t)
	s.misbehave = func(_ int, w http.ResponseWriter, _ *http.Request) bool {
		w.WriteHeader(http.StatusForbidden)
		return true
	}

	err := s.transfer().Download(context.Background(), s.slot, filepath.Join(t.TempDir(), "image"))

	var remote *RemoteError
	if !errors.As(err, &remote) || remote.StatusCode != http.StatusForbidden {
		t.Fatal(err)
	}
	if ranges := s.requestedRanges(); len(ranges) != 1 {
		t.Fatalf("retried a refused link %d times", len(ranges))
	}
}

func TestDownloadDoesNotRetryAnArchiveLargerThanAnImage(t *testing.T) {
	s := newObjectServer(t)
	transfer := s.transfer()
	transfer.MaxBytes = 1 << 10

	if err := transfer.Download(context.Background(), s.slot, filepath.Join(t.TempDir(), "image")); !errors.Is(err, errArchiveTooLarge) {
		t.Fatal(err)
	}
	if ranges := s.requestedRanges(); len(ranges) != 1 {
		t.Fatalf("retried an oversized archive %d times", len(ranges))
	}
}

func TestDownloadReportsProgressWhenItsBudgetEnds(t *testing.T) {
	s := newObjectServer(t)
	s.misbehave = func(_ int, w http.ResponseWriter, r *http.Request) bool {
		w.Header().Set("Content-Length", strconv.Itoa(len(s.archive)))
		w.WriteHeader(http.StatusOK)
		w.Write(s.archive[:len(s.archive)/2])
		w.(http.Flusher).Flush()
		<-r.Context().Done()
		return true
	}
	transfer := s.transfer()
	transfer.stallTimeout = time.Minute
	path := filepath.Join(t.TempDir(), "image")
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()

	err := transfer.Download(ctx, s.slot, path)

	if !errors.Is(err, ErrDownloadIncomplete) || !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("a download cut off by its budget did not report its progress:", err)
	}
	if info, statErr := os.Stat(path + ".part"); statErr != nil || info.Size() != int64(len(s.archive)/2) {
		t.Fatal("did not keep the bytes it received:", statErr)
	}
}
