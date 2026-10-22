package cachevolumes

import (
	"bytes"
	"context"
	"crypto/md5"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
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

	// partBytes, when set, makes the host upload in parts of this size and
	// storage accept them.
	partBytes int64

	mu          sync.Mutex
	operations  []string
	puts        int
	stored      []byte
	parts       map[int][]byte
	aborted     bool
	inFlight    int
	maxInFlight int
	metadata    func(operation string, count int, w http.ResponseWriter) bool
	object      func(put int, w http.ResponseWriter, r *http.Request) bool
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
	s := &uploadServer{archive: archive, path: path, parts: map[int][]byte{}}
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
			switch operation {
			case "upload":
				if body["multipart"] == true && s.partBytes > 0 {
					json.NewEncoder(w).Encode(map[string]any{"upload_id": "upload-1"})
					return
				}
				json.NewEncoder(w).Encode(map[string]any{"upload_url": s.URL + "/object?X-Amz-Signature=secret", "checksum_sha256": "checksum"})
			case "upload_parts":
				var links []map[string]any
				for _, entry := range body["parts"].([]any) {
					part := entry.(map[string]any)
					signed := url.QueryEscape(part["content_md5"].(string))
					links = append(links, map[string]any{"part_number": part["part_number"], "url": fmt.Sprintf("%s/part/%v?md5=%s&X-Amz-Signature=secret", s.URL, part["part_number"], signed)})
				}
				json.NewEncoder(w).Encode(map[string]any{"parts": links})
			case "complete":
				s.complete(t, body)
				json.NewEncoder(w).Encode(map[string]any{})
			case "abort":
				s.mu.Lock()
				s.aborted = true
				s.mu.Unlock()
				json.NewEncoder(w).Encode(map[string]any{})
			default:
				json.NewEncoder(w).Encode(map[string]any{"generation": 2})
			}
			return
		}
		s.mu.Lock()
		s.puts++
		s.inFlight++
		s.maxInFlight = max(s.maxInFlight, s.inFlight)
		put, object := s.puts, s.object
		s.mu.Unlock()
		defer func() {
			s.mu.Lock()
			s.inFlight--
			s.mu.Unlock()
		}()
		part, isPart := strings.CutPrefix(r.URL.Path, "/part/")
		if !isPart && r.Header.Get("x-amz-checksum-sha256") != "checksum" {
			t.Error("upload without its signed checksum")
		}
		if object != nil && object(put, w, r) {
			return
		}
		received, err := io.ReadAll(r.Body)
		if err != nil {
			return
		}
		if !isPart {
			s.mu.Lock()
			s.stored = received
			s.mu.Unlock()
			w.WriteHeader(http.StatusOK)
			return
		}
		sum := md5.Sum(received)
		if md5 := base64.StdEncoding.EncodeToString(sum[:]); r.Header.Get("Content-MD5") != md5 || r.URL.Query().Get("md5") != md5 {
			w.WriteHeader(http.StatusBadRequest)
			w.Write([]byte("<Error><Code>BadDigest</Code></Error>"))
			return
		}
		number, _ := strconv.Atoi(part)
		s.mu.Lock()
		s.parts[number] = received
		s.mu.Unlock()
		w.Header().Set("ETag", fmt.Sprintf(`"etag-%d"`, number))
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
		partBytes: s.partBytes, uploadParallelism: 4,
	}
}

// complete assembles the parts the host names, each with the ETag storage gave it.
func (s *uploadServer) complete(t *testing.T, body map[string]any) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var assembled []byte
	for i, entry := range body["parts"].([]any) {
		part := entry.(map[string]any)
		number := int(part["part_number"].(float64))
		if number != i+1 || part["etag"] != fmt.Sprintf(`"etag-%d"`, number) {
			t.Errorf("completed with part %v", part)
		}
		assembled = append(assembled, s.parts[number]...)
	}
	s.stored = assembled
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

func newMultipartServer(t *testing.T, partBytes int64) *uploadServer {
	s := newUploadServer(t)
	s.partBytes = partBytes
	return s
}

func TestPublishUploadsALargeArchiveInParallelParts(t *testing.T) {
	s := newMultipartServer(t, 512<<10)

	if generation, err := s.publish(t); err != nil || generation != 2 {
		t.Fatal(generation, err)
	}

	s.uploadedWholeArchive(t)
	operations, puts := s.calls()
	if strings.Join(operations, ",") != "upload,upload_parts,complete,publish" || puts != 8 {
		t.Fatalf("operations %v, puts %d", operations, puts)
	}
	if s.maxInFlight < 2 {
		t.Fatal("parts were not sent in parallel")
	}
}

func TestPublishResendsOnlyThePartWhoseConnectionDropped(t *testing.T) {
	s := newMultipartServer(t, 512<<10)
	dropped := false
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		if r.URL.Path == "/part/3" && !dropped {
			dropped = true
			io.CopyN(io.Discard, r.Body, 256<<10)
			if conn, _, err := w.(http.Hijacker).Hijack(); err == nil {
				conn.Close()
			}
			return true
		}
		return false
	}

	if generation, err := s.publish(t); err != nil || generation != 2 {
		t.Fatal(generation, err)
	}

	s.uploadedWholeArchive(t)
	operations, puts := s.calls()
	if strings.Join(operations, ",") != "upload,upload_parts,upload_parts,complete,publish" || puts != 9 {
		t.Fatalf("operations %v, puts %d: the retry must resume the same upload and send one part", operations, puts)
	}
}

func TestPublishRetriesAPartTheObjectStoreFailed(t *testing.T) {
	s := newMultipartServer(t, 512<<10)
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
	if _, puts := s.calls(); puts != 9 {
		t.Fatal("puts", puts)
	}
}

func TestPublishKeepsGoingWhileAttemptsStoreParts(t *testing.T) {
	// 41 parts in batches of 16: the first part of each of the first four
	// batches fails, more failed attempts than uploadAttempts, but all but the
	// last stored other parts.
	s := newMultipartServer(t, 100<<10)
	failedBatches := map[int]bool{}
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		s.mu.Lock()
		batch := 0
		for _, operation := range s.operations {
			if operation == "upload_parts" {
				batch++
			}
		}
		fail := batch <= uploadAttempts && !failedBatches[batch]
		failedBatches[batch] = true
		s.mu.Unlock()
		if fail {
			io.Copy(io.Discard, r.Body)
			w.WriteHeader(http.StatusServiceUnavailable)
			return true
		}
		return false
	}

	if generation, err := s.publish(t); err != nil || generation != 2 {
		t.Fatal(generation, err)
	}
	s.uploadedWholeArchive(t)
}

func TestPublishAbortsAMultipartUploadOnceTheLineageAdvanced(t *testing.T) {
	s := newMultipartServer(t, 512<<10)
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		if put == 1 {
			io.Copy(io.Discard, r.Body)
			w.WriteHeader(http.StatusInternalServerError)
			return true
		}
		return false
	}
	s.metadata = func(operation string, count int, w http.ResponseWriter) bool {
		if operation == "upload_parts" && count == 2 {
			w.WriteHeader(http.StatusConflict)
			return true
		}
		return false
	}

	if _, err := s.publish(t); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if operations, _ := s.calls(); operations[len(operations)-1] != "abort" || !s.aborted {
		t.Fatalf("did not abort the upload: %v", operations)
	}
}

func TestPublishAbortsAMultipartUploadStorageRefused(t *testing.T) {
	s := newMultipartServer(t, 512<<10)
	s.object = func(put int, w http.ResponseWriter, r *http.Request) bool {
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(http.StatusForbidden)
		w.Write([]byte("<Error><Code>AccessDenied</Code></Error>"))
		return true
	}

	_, err := s.publish(t)

	var remote *RemoteError
	if !errors.As(err, &remote) || remote.Code != "AccessDenied" || !s.aborted {
		t.Fatal(err, s.aborted)
	}
	if operations, _ := s.calls(); strings.Count(strings.Join(operations, ","), "upload_parts") != 1 {
		t.Fatalf("retried a refused part: %v", operations)
	}
}

func TestPublishRetriesOnlyTheCompletionOfAStoredMultipartUpload(t *testing.T) {
	s := newMultipartServer(t, 512<<10)
	s.metadata = func(operation string, count int, w http.ResponseWriter) bool {
		if operation == "complete" && count == 1 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return true
		}
		return false
	}

	if generation, err := s.publish(t); err != nil || generation != 2 {
		t.Fatal(generation, err)
	}
	operations, puts := s.calls()
	if strings.Join(operations, ",") != "upload,upload_parts,complete,complete,publish" || puts != 8 {
		t.Fatalf("operations %v, puts %d", operations, puts)
	}
}

func TestSmallArchivesStillUploadInOnePut(t *testing.T) {
	s := newMultipartServer(t, 4<<20)

	if generation, err := s.publish(t); err != nil || generation != 2 {
		t.Fatal(generation, err)
	}
	if operations, puts := s.calls(); strings.Join(operations, ",") != "upload,publish" || puts != 1 {
		t.Fatalf("operations %v, puts %d", operations, puts)
	}
}
