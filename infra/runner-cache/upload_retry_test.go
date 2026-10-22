package cachevolumes

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// uploadServer answers the image metadata requests and stores PUT archives the
// way object storage does, through handlers the test can make misbehave.
type uploadServer struct {
	*httptest.Server
	archive []byte
	path    string

	mu         sync.Mutex
	operations []string
	puts       int
	stored     []byte
	metadata   func(operation string, count int, w http.ResponseWriter) bool
	object     func(put int, w http.ResponseWriter, r *http.Request) bool
}

func newUploadServer(t *testing.T) *uploadServer {
	t.Helper()
	archive := make([]byte, 4<<20)
	if _, err := rand.Read(archive); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "image.zst")
	if err := os.WriteFile(path, archive, 0600); err != nil {
		t.Fatal(err)
	}
	s := &uploadServer{archive: archive, path: path}
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			var body map[string]any
			json.NewDecoder(r.Body).Decode(&body)
			operation, _ := body["operation"].(string)
			s.mu.Lock()
			s.operations = append(s.operations, operation)
			count, metadata := 0, s.metadata
			for _, seen := range s.operations {
				if seen == operation {
					count++
				}
			}
			s.mu.Unlock()
			if metadata != nil && metadata(operation, count, w) {
				return
			}
			if operation == "upload" {
				json.NewEncoder(w).Encode(map[string]any{"upload_url": s.URL + "/object?X-Amz-Signature=secret", "checksum_sha256": "checksum"})
				return
			}
			json.NewEncoder(w).Encode(map[string]any{"generation": 2})
			return
		}
		s.mu.Lock()
		s.puts++
		put, object := s.puts, s.object
		s.mu.Unlock()
		if r.Header.Get("x-amz-checksum-sha256") != "checksum" {
			t.Error("upload without its signed checksum")
		}
		if object != nil && object(put, w, r) {
			return
		}
		received, err := io.ReadAll(r.Body)
		if err != nil {
			return
		}
		s.mu.Lock()
		s.stored = received
		s.mu.Unlock()
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *uploadServer) transfer() *HTTPTransfer {
	return &HTTPTransfer{
		URL: s.URL, Node: "node", Client: s.Client(), MaxBytes: 8 << 20,
		Token:        func(context.Context) (string, error) { return "token", nil },
		stallTimeout: 200 * time.Millisecond, retryBackoff: time.Millisecond,
	}
}

func (s *uploadServer) publish(t *testing.T) (int64, error) {
	t.Helper()
	slot := Slot{Identity: identity(first)}
	slot.BaseGeneration = 1
	return s.transfer().Publish(slot, s.path, strings.Repeat("a", 40), strings.Repeat("b", 64))
}

func (s *uploadServer) calls() ([]string, int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.operations...), s.puts
}

// dropMidBody reads half the archive and closes the connection without answering.
func (s *uploadServer) dropMidBody(w http.ResponseWriter, r *http.Request) {
	io.CopyN(io.Discard, r.Body, int64(len(s.archive)/2))
	conn, _, err := w.(http.Hijacker).Hijack()
	if err == nil {
		conn.Close()
	}
}

func (s *uploadServer) uploadedWholeArchive(t *testing.T) {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if !bytes.Equal(s.stored, s.archive) {
		t.Fatalf("object store holds %d of %d archive bytes", len(s.stored), len(s.archive))
	}
}

func TestPublishRetriesAnUploadWhoseConnectionDroppedMidBody(t *testing.T) {
	s := newUploadServer(t)
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		if put == 1 {
			s.dropMidBody(w, r)
			return true
		}
		return false
	}

	generation, err := s.publish(t)

	if err != nil || generation != 2 {
		t.Fatal(generation, err)
	}
	s.uploadedWholeArchive(t)
	operations, puts := s.calls()
	if strings.Join(operations, ",") != "upload,upload,publish" || puts != 2 {
		t.Fatalf("operations %v, puts %d: each attempt must ask for a fresh link", operations, puts)
	}
	if _, err := os.Stat(s.path); err != nil {
		t.Fatal("publication removed the archive it was given", err)
	}
}

func TestPublishRetriesAnUploadTheObjectStoreFailed(t *testing.T) {
	s := newUploadServer(t)
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		if put == 1 {
			io.Copy(io.Discard, r.Body)
			w.WriteHeader(http.StatusBadGateway)
			return true
		}
		return false
	}

	if generation, err := s.publish(t); err != nil || generation != 2 {
		t.Fatal(generation, err)
	}
	s.uploadedWholeArchive(t)
	if _, puts := s.calls(); puts != 2 {
		t.Fatal("puts", puts)
	}
}

func TestPublishAbandonsAStalledUploadAndRetries(t *testing.T) {
	s := newUploadServer(t)
	// The server notices a closed connection only once it reads the body again.
	release := make(chan struct{})
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		if put == 1 {
			io.CopyN(io.Discard, r.Body, 1<<20)
			<-release
			return true
		}
		return false
	}

	generation, err := s.publish(t)
	close(release)

	if err != nil || generation != 2 {
		t.Fatal("a stalled upload was not abandoned:", generation, err)
	}
	s.uploadedWholeArchive(t)
}

func TestPublishStopsRetryingOnceTheLineageAdvanced(t *testing.T) {
	s := newUploadServer(t)
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		s.dropMidBody(w, r)
		return true
	}
	s.metadata = func(operation string, count int, w http.ResponseWriter) bool {
		if operation == "upload" && count == 2 {
			w.WriteHeader(http.StatusConflict)
			return true
		}
		return false
	}

	if _, err := s.publish(t); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if _, puts := s.calls(); puts != 1 {
		t.Fatal("uploaded again after the lineage advanced:", puts)
	}
}

func TestPublishRetriesOnlyTheFastForwardAfterTheUploadLanded(t *testing.T) {
	s := newUploadServer(t)
	s.metadata = func(operation string, count int, w http.ResponseWriter) bool {
		if operation == "publish" && count == 1 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return true
		}
		return false
	}

	if generation, err := s.publish(t); err != nil || generation != 2 {
		t.Fatal(generation, err)
	}
	operations, puts := s.calls()
	if strings.Join(operations, ",") != "upload,publish,publish" || puts != 1 {
		t.Fatalf("operations %v, puts %d", operations, puts)
	}
}

func TestPublishDoesNotRetryARefusedUpload(t *testing.T) {
	s := newUploadServer(t)
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusForbidden)
		w.Write([]byte("<Error><Code>SignatureDoesNotMatch</Code></Error>"))
		return true
	}

	_, err := s.publish(t)

	var remote *RemoteError
	if !errors.As(err, &remote) || remote.StatusCode != http.StatusForbidden || remote.Code != "SignatureDoesNotMatch" {
		t.Fatal(err)
	}
	if _, puts := s.calls(); puts != 1 {
		t.Fatal("retried a refused upload:", puts)
	}
}

func TestPublishGivesUpAfterItsAttempts(t *testing.T) {
	s := newUploadServer(t)
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("<Error><Code>SlowDown</Code></Error>"))
		return true
	}

	_, err := s.publish(t)

	if err == nil || err.Error() != "image upload status 503 SlowDown" {
		t.Fatal(err)
	}
	if _, puts := s.calls(); puts != uploadAttempts {
		t.Fatal("puts", puts)
	}
}

func TestTransferErrorsKeepTheNetworkFailureWithoutTheURL(t *testing.T) {
	s := newUploadServer(t)
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		s.dropMidBody(w, r)
		return true
	}

	_, err := s.publish(t)

	if !errors.Is(err, errTransport) || !strings.HasPrefix(err.Error(), "image upload failed: transport error: ") {
		t.Fatal(err)
	}
	if strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), "/object") {
		t.Fatal("leaked the upload URL:", err)
	}
}
