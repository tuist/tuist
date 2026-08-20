package podagent

import (
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

// truncatingServer serves a fixed object and cuts the first `truncate`
// responses short, which is what production sees: object storage closes the
// transfer mid-body, curl reports exit 18, and the bytes already on disk are
// good. It honours Range so a resumed attempt asks only for the remainder, and
// records every request so a test can prove the remainder is all that was
// re-sent.
type truncatingServer struct {
	body []byte
	// truncate is how many more responses to cut short.
	truncate int
	// ignoreRange, when set, answers the next ranged request with the whole
	// object and a 200 — a server that does not honour Range at all.
	ignoreRange bool

	mu     sync.Mutex
	starts []int64
	served int
}

func (s *truncatingServer) handle(w http.ResponseWriter, req *http.Request) {
	s.mu.Lock()
	start := int64(0)
	if raw := req.Header.Get("Range"); raw != "" && !s.ignoreRange {
		start, _ = strconv.ParseInt(strings.TrimSuffix(strings.TrimPrefix(raw, "bytes="), "-"), 10, 64)
	}
	s.starts = append(s.starts, start)
	cut := s.truncate > 0
	if cut {
		s.truncate--
	}
	s.mu.Unlock()

	chunk := s.body[start:]
	if start > 0 && !s.ignoreRange {
		w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, len(s.body)-1, len(s.body)))
		w.Header().Set("Content-Length", strconv.Itoa(len(chunk)))
		w.WriteHeader(http.StatusPartialContent)
	} else {
		w.Header().Set("Content-Length", strconv.Itoa(len(chunk)))
		w.WriteHeader(http.StatusOK)
	}
	if cut {
		// Declare the full length, deliver a third of it, then abort the
		// connection: curl's "transfer closed with N bytes remaining to read".
		_, _ = w.Write(chunk[:len(chunk)/3])
		s.recordServed(len(chunk) / 3)
		panic(http.ErrAbortHandler)
	}
	_, _ = w.Write(chunk)
	s.recordServed(len(chunk))
}

func (s *truncatingServer) recordServed(n int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.served += n
}

func (s *truncatingServer) requests() ([]int64, int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]int64(nil), s.starts...), s.served
}

// masterObject is a deterministic stand-in for the account's master image, big
// enough that a third of it is a meaningful prefix.
func masterObject() []byte {
	b := make([]byte, 96*1024)
	for i := range b {
		b[i] = byte(i % 251)
	}
	return b
}

func objectDigest(b []byte) string {
	h := sha1.Sum(b)
	return hex.EncodeToString(h[:])
}

// A transfer the far end cut short must cost only the bytes it did not deliver.
// Restarting from zero instead would push the whole multi-gigabyte object
// through the same path that just failed — the amplification that makes a
// shared bottleneck worse rather than better.
func TestConvergeDownloadResumesInsteadOfRestarting(t *testing.T) {
	body := masterObject()
	srv := &truncatingServer{body: body, truncate: 1}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	dst := filepath.Join(t.TempDir(), "head.sparseimage")
	r := &Reconciler{ConvergeDownloadAttempts: 3, ConvergeDownloadBackoff: time.Millisecond}

	if err := r.downloadMasterImage(ts.URL, dst); err != nil {
		t.Fatalf("download after one truncated transfer: %v", err)
	}

	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read downloaded image: %v", err)
	}
	if objectDigest(got) != objectDigest(body) {
		t.Fatalf("resumed image is %d bytes and does not match the object (%d bytes)", len(got), len(body))
	}

	starts, served := srv.requests()
	if len(starts) != 2 {
		t.Fatalf("requests = %v, want two (the truncated one and its resume)", starts)
	}
	if starts[1] == 0 {
		t.Fatal("the retry restarted from byte 0 instead of resuming")
	}
	if served >= 2*len(body) {
		t.Fatalf("served %d bytes for a %d-byte object; the retry re-sent the whole thing", served, len(body))
	}
}

// The retry is bounded: a path that keeps closing transfers must not hold a
// goroutine and staging disk indefinitely, and convergence stays best-effort.
func TestConvergeDownloadGivesUpAfterItsAttempts(t *testing.T) {
	srv := &truncatingServer{body: masterObject(), truncate: 99}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	dst := filepath.Join(t.TempDir(), "head.sparseimage")
	r := &Reconciler{ConvergeDownloadAttempts: 3, ConvergeDownloadBackoff: time.Millisecond}

	err := r.downloadMasterImage(ts.URL, dst)
	if err == nil {
		t.Fatal("a transfer that never completes must not report success")
	}
	if !strings.Contains(err.Error(), "curl master image") {
		t.Fatalf("error lost its context: %v", err)
	}
	if starts, _ := srv.requests(); len(starts) != 3 {
		t.Fatalf("attempts = %d, want 3", len(starts))
	}
	// Nothing partial is left behind for the digest check to measure.
	if _, err := os.Stat(dst); !os.IsNotExist(err) {
		t.Fatalf("partial download survived a failed fetch: %v", err)
	}
}

// curl refuses to append when it asked to resume and got the whole object back,
// rather than corrupting the file. Recovery is to drop the partial and start the
// next attempt clean, so a backend that stops honouring Range costs the resume
// but never the convergence.
func TestConvergeDownloadRestartsWhenTheServerWillNotResume(t *testing.T) {
	body := masterObject()
	srv := &truncatingServer{body: body, truncate: 1, ignoreRange: true}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	dst := filepath.Join(t.TempDir(), "head.sparseimage")
	r := &Reconciler{ConvergeDownloadAttempts: 3, ConvergeDownloadBackoff: time.Millisecond}

	if err := r.downloadMasterImage(ts.URL, dst); err != nil {
		t.Fatalf("download against a server that ignores Range: %v", err)
	}

	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read downloaded image: %v", err)
	}
	if objectDigest(got) != objectDigest(body) {
		t.Fatalf("restarted image is %d bytes and does not match the object (%d bytes)", len(got), len(body))
	}
	// Truncated, then a resume the server would not honour, then a clean restart.
	if starts, _ := srv.requests(); len(starts) != 3 {
		t.Fatalf("requests = %v, want three (truncated, refused resume, clean restart)", starts)
	}
}

// End to end: a HEAD whose transfer was cut short is still adopted, because the
// resume completes it and the digest check then passes on the whole object.
func TestConvergeMasterAdoptsAHeadWhoseTransferWasTruncated(t *testing.T) {
	body := masterObject()
	srv := &truncatingServer{body: body, truncate: 1}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	m, _ := newTestManager(t, 100)
	statusDir := t.TempDir()
	stageHead(t, statusDir, volumeHead{Generation: 6, Digest: objectDigest(body), DownloadURL: ts.URL})
	r := &Reconciler{
		Volumes:                  m,
		ConvergeHeadWaitInterval: time.Millisecond,
		ConvergeHeadWaitAttempts: 2,
		ConvergeDownloadAttempts: 3,
		ConvergeDownloadBackoff:  time.Millisecond,
	}

	r.convergeMaster("vm1", statusDir, ReservedTuistCacheVolume, "42")

	if !masterExists(m, "42") {
		t.Fatal("a resumable truncation lost the convergence")
	}
	if gen, err := m.MasterGeneration("42", ReservedTuistCacheVolume); err != nil || gen != 6 {
		t.Fatalf("master generation = %d (%v), want 6", gen, err)
	}
}

// Resume is only safe because the digest check still decides. Bytes stitched
// together across attempts get exactly the same scrutiny as a single transfer's,
// so a resumed fetch that does not reproduce the HEAD is discarded and reported
// like any other mismatch.
func TestConvergeMasterRejectsAResumedTransferThatIsNotTheHead(t *testing.T) {
	body := masterObject()
	// The object served is not the one the HEAD advertises, and it arrives in two
	// pieces — the digest of the stitched result is what must be rejected.
	srv := &truncatingServer{body: body, truncate: 1}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	m, _ := newTestManager(t, 100)
	statusDir := t.TempDir()
	advertised := objectDigest([]byte("a different master entirely"))
	stageHead(t, statusDir, volumeHead{Generation: 6, Digest: advertised, DownloadURL: ts.URL})
	r := &Reconciler{
		Volumes:                  m,
		ConvergeHeadWaitInterval: time.Millisecond,
		ConvergeHeadWaitAttempts: 2,
		ConvergeDownloadAttempts: 3,
		ConvergeDownloadBackoff:  time.Millisecond,
	}

	r.convergeMaster("vm1", statusDir, ReservedTuistCacheVolume, "42")

	if masterExists(m, "42") {
		t.Fatal("adopted a resumed image whose digest did not match the HEAD")
	}
	staged, err := os.ReadFile(filepath.Join(statusDir, unverifiableHeadFile))
	if err != nil || string(staged) != advertised {
		t.Fatalf("resumed mismatch not reported for the guest: %q (%v)", staged, err)
	}
}

// The counters are the point of the exercise: converged_total only ever counted
// successes, so this failure mode was invisible to alerting and had to be found
// by reading logs.
func TestConvergeMasterCountsDownloadFailuresAndRetries(t *testing.T) {
	srv := &truncatingServer{body: masterObject(), truncate: 99}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	failedBefore := testutil.ToFloat64(cacheVolumeConvergeFailedTotal.WithLabelValues("download"))
	retriesBefore := testutil.ToFloat64(cacheVolumeConvergeDownloadRetriesTotal)

	m, _ := newTestManager(t, 100)
	statusDir := t.TempDir()
	stageHead(t, statusDir, volumeHead{Generation: 6, Digest: objectDigest(masterObject()), DownloadURL: ts.URL})
	r := &Reconciler{
		Volumes:                  m,
		ConvergeHeadWaitInterval: time.Millisecond,
		ConvergeHeadWaitAttempts: 2,
		ConvergeDownloadAttempts: 3,
		ConvergeDownloadBackoff:  time.Millisecond,
	}

	r.convergeMaster("vm1", statusDir, ReservedTuistCacheVolume, "42")

	if got := testutil.ToFloat64(cacheVolumeConvergeFailedTotal.WithLabelValues("download")); got != failedBefore+1 {
		t.Fatalf("converge_failed_total{download} = %v, want %v", got, failedBefore+1)
	}
	// Two of the three attempts were retries of a transfer that died mid-flight.
	if got := testutil.ToFloat64(cacheVolumeConvergeDownloadRetriesTotal); got != retriesBefore+2 {
		t.Fatalf("converge_download_retries_total = %v, want %v", got, retriesBefore+2)
	}
}

// Every failure reason exists as a series from registration, so "digest
// mismatches stay at zero" is something a panel can read rather than "No data".
func TestConvergeFailureSeriesInitialized(t *testing.T) {
	if got := testutil.CollectAndCount(cacheVolumeConvergeFailedTotal); got < 4 {
		t.Fatalf("converge failure series = %d, want >= 4 (all reasons pre-initialized)", got)
	}
}
