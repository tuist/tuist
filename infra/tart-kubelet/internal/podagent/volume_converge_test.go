package podagent

import (
	"bytes"
	"context"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	k8stesting "k8s.io/client-go/testing"
)

// imageServer serves content like an object store: whole, or from the Range a
// resuming client asks for. It records every Range header it was sent.
type imageServer struct {
	*httptest.Server
	requests atomic.Int32
	mu       sync.Mutex
	ranges   []string
}

func serveImage(t *testing.T, content []byte) *imageServer {
	t.Helper()
	s := &imageServer{}
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.requests.Add(1)
		s.mu.Lock()
		s.ranges = append(s.ranges, r.Header.Get("Range"))
		s.mu.Unlock()
		http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(content))
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *imageServer) rangeHeaders() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.ranges...)
}

// headFor is the HEAD a promoting guest would publish for content: the fake
// backend's inventory digest (sha1 of the bytes) and the content digest.
func headFor(content []byte, generation int, url string) volumeHead {
	inventory := sha1.Sum(content)
	sum := sha256.Sum256(content)
	return volumeHead{
		Generation:    generation,
		Digest:        hex.EncodeToString(inventory[:]),
		ContentDigest: hex.EncodeToString(sum[:]),
		DownloadURL:   url,
	}
}

func jobRequest(account string, head volumeHead) convergeRequest {
	return convergeRequest{
		key:    masterKey{account: account, volume: ReservedTuistCacheVolume},
		head:   head,
		source: convergeSourceJob,
	}
}

func drain(w *ConvergeWorker) {
	for w.step(context.Background()) {
	}
}

// startJob materializes a job on the host, which is what makes it busy.
func startJob(t *testing.T, m *VolumeManager, vm, account string) VolumeAttachment {
	t.Helper()
	att := mustAllocate(t, m, vm)
	if _, _, err := m.Materialize(att, account); err != nil {
		t.Fatalf("Materialize: %v", err)
	}
	return att
}

func TestConvergeAlongsideJobs(t *testing.T) {
	const gibBytes = uint64(1 << 30)
	for _, tc := range []struct {
		name       string
		physical   uint64
		advertised int
		want       bool
	}{
		// An M2-L promises 14 of its 16 GB to its guest, which production runs
		// in 8-15 GB of swap.
		{name: "M2-L", physical: 16 * gibBytes, advertised: 14336, want: false},
		// An M4-XL promises 28 of its 64 GB to its two guests.
		{name: "M4-XL", physical: 64 * gibBytes, advertised: 28672, want: true},
		{name: "advertises more than it has", physical: 16 * gibBytes, advertised: 32768, want: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := ConvergeAlongsideJobs(tc.physical, tc.advertised); got != tc.want {
				t.Fatalf("ConvergeAlongsideJobs = %v, want %v", got, tc.want)
			}
		})
	}
}

// A host whose guest already takes its memory must not stream a master through
// it while the guest runs a job: the download waits for the job to end.
func TestConvergeWaitsUntilNoJobRuns(t *testing.T) {
	content := []byte("head-of-42")
	srv := serveImage(t, content)
	m, _ := newTestManager(t, 100)
	job := startJob(t, m, "vm-job", "7")

	w := newTestConvergeWorker(m)
	w.Enqueue(jobRequest("42", headFor(content, 4, srv.URL)))
	if w.step(context.Background()) {
		t.Fatal("the worker ran while a job was running")
	}
	if got := srv.requests.Load(); got != 0 {
		t.Fatalf("downloaded %d times while a job was running", got)
	}

	if _, err := m.Finalize(job, "7", true, false); err != nil {
		t.Fatalf("Finalize: %v", err)
	}
	drain(w)
	if gen, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); gen != 4 {
		t.Fatalf("generation after the job ended = %d, want 4", gen)
	}
}

func TestConvergeRunsBesideJobsWhenTheHostHasTheMemory(t *testing.T) {
	content := []byte("head-of-42")
	srv := serveImage(t, content)
	m, _ := newTestManager(t, 100)
	startJob(t, m, "vm-job", "7")

	w := newTestConvergeWorker(m)
	w.AlongsideJobs = true
	w.Enqueue(jobRequest("42", headFor(content, 4, srv.URL)))
	drain(w)
	if gen, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); gen != 4 {
		t.Fatalf("generation = %d, want 4", gen)
	}
}

// A job that lands mid-download stops it, and the download picks up from the
// bytes it already has once the host is idle, rather than starting over.
func TestConvergeYieldsToAJobAndResumes(t *testing.T) {
	content := bytes.Repeat([]byte("0123456789abcdef"), 1<<16) // 1 MiB
	half := len(content) / 2
	halfSent := make(chan struct{})
	var calls atomic.Int32
	var mu sync.Mutex
	var resumedFrom string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) == 1 {
			w.Header().Set("Content-Length", strconv.Itoa(len(content)))
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(content[:half])
			w.(http.Flusher).Flush()
			close(halfSent)
			<-r.Context().Done()
			return
		}
		mu.Lock()
		resumedFrom = r.Header.Get("Range")
		mu.Unlock()
		http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(content))
	}))
	defer srv.Close()

	m, _ := newTestManager(t, 100)
	w := newTestConvergeWorker(m)
	w.Enqueue(jobRequest("42", headFor(content, 4, srv.URL)))

	stepped := make(chan bool)
	go func() { stepped <- w.step(context.Background()) }()
	<-halfSent
	job := startJob(t, m, "vm-job", "7")
	if more := <-stepped; more {
		t.Fatal("the worker kept going after a job landed")
	}

	partial, err := os.Stat(filepath.Join(m.ConvergeStagingDir("42", ReservedTuistCacheVolume), "head-4.sparseimage"))
	if err != nil || partial.Size() == 0 {
		t.Fatalf("no partial download kept for the resume: %v", err)
	}
	if gen, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); gen != 0 {
		t.Fatalf("installed generation %d from a paused download", gen)
	}

	if _, err := m.Finalize(job, "7", true, false); err != nil {
		t.Fatalf("Finalize: %v", err)
	}
	drain(w)
	if gen, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); gen != 4 {
		t.Fatalf("generation after resuming = %d, want 4", gen)
	}
	mu.Lock()
	defer mu.Unlock()
	if want := "bytes=" + strconv.FormatInt(partial.Size(), 10) + "-"; resumedFrom != want {
		t.Fatalf("resume asked for Range %q, want %q", resumedFrom, want)
	}
}

// A transfer the object store closes early (curl's exit 18) resumes instead of
// failing the convergence.
func TestConvergeResumesATruncatedTransfer(t *testing.T) {
	content := bytes.Repeat([]byte("fedcba9876543210"), 1<<14)
	half := len(content) / 2
	var calls atomic.Int32
	var mu sync.Mutex
	var ranges []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		ranges = append(ranges, r.Header.Get("Range"))
		mu.Unlock()
		if calls.Add(1) == 1 {
			w.Header().Set("Content-Length", strconv.Itoa(len(content)))
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(content[:half])
			return
		}
		http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(content))
	}))
	defer srv.Close()

	m, _ := newTestManager(t, 100)
	w := newTestConvergeWorker(m)
	if got := w.converge(context.Background(), jobRequest("42", headFor(content, 4, srv.URL))); got != "converged" {
		t.Fatalf("converge = %q, want converged", got)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(ranges) != 2 || ranges[1] != "bytes="+strconv.Itoa(half)+"-" {
		t.Fatalf("Range headers = %q; want the retry to resume from byte %d", ranges, half)
	}
}

// A master larger than the volume can hold beside its watermark would be the
// evictor's first victim, so it is not downloaded at all.
func TestConvergeDeclinesAMasterTheHostCannotKeep(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		// Only the headers matter: the host decides before reading the body.
		w.Header().Set("Content-Length", strconv.FormatUint(gib, 10))
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	root := t.TempDir()
	// A 2 GiB volume with a 1 GiB cap keeps 1.2 GiB free, so it can keep 0.8.
	m := NewVolumeManager(root, 1, &fakeBackend{totalBytes: 2 * gib, perMaster: gib, root: root})
	messages := captureLogs(t)

	w := newTestConvergeWorker(m)
	if got := w.converge(context.Background(), jobRequest("42", volumeHead{Generation: 4, DownloadURL: srv.URL})); got != "too_large" {
		t.Fatalf("converge = %q, want too_large", got)
	}
	if _, err := os.Stat(m.ConvergeStagingDir("42", ReservedTuistCacheVolume)); !os.IsNotExist(err) {
		t.Fatalf("staging left behind for a declined master: %v", err)
	}
	for _, msg := range messages() {
		if strings.Contains(msg, "larger than this host can keep") {
			return
		}
	}
	t.Fatalf("no log line explains the decline; got %v", messages())
}

// A job's convergence makes room the way admission does, evicting the least
// recently used masters. A prefetch is speculative and may only use space that
// is already free, so it never evicts a master a job used.
func TestConvergeEvictsForAJobButNotForAPrefetch(t *testing.T) {
	content := []byte("head-of-42")
	srv := serveImage(t, content)
	root := t.TempDir()
	m := NewVolumeManager(root, 1, &fakeBackend{totalBytes: 4 * gib, perMaster: gib, root: root})
	base := time.Now().Add(-time.Hour)
	for i, account := range []string{"1", "2", "3"} {
		seedMasterGen(t, m, account, masterImageContent(account), 1)
		stamp := base.Add(time.Duration(i) * time.Minute)
		if err := os.Chtimes(m.masterImage(account, ReservedTuistCacheVolume), stamp, stamp); err != nil {
			t.Fatal(err)
		}
	}
	w := newTestConvergeWorker(m)

	prefetch := jobRequest("42", headFor(content, 4, srv.URL))
	prefetch.source = convergeSourcePrefetch
	if got := w.converge(context.Background(), prefetch); got != "no_room" {
		t.Fatalf("prefetch converge = %q, want no_room", got)
	}
	for _, account := range []string{"1", "2", "3"} {
		if !masterExists(m, account) {
			t.Fatalf("a prefetch evicted account %s's master", account)
		}
	}

	if got := w.converge(context.Background(), jobRequest("42", headFor(content, 4, srv.URL))); got != "converged" {
		t.Fatalf("job converge = %q, want converged", got)
	}
	if masterExists(m, "1") {
		t.Fatal("the least recently used master was not evicted for the job's convergence")
	}
	if !masterExists(m, "2") || !masterExists(m, "3") || !masterExists(m, "42") {
		t.Fatal("evicted more than the convergence needed")
	}
}

// The job that relayed a HEAD has usually finished by the time the worker finds
// the object does not reproduce it, so the disproof is staged into the next job
// for the volume, whose promote can retire it. The host does not download a HEAD
// it has already disproved.
func TestConvergeCarriesADisproofToTheNextJob(t *testing.T) {
	served := []byte("not-the-advertised-head")
	srv := serveImage(t, served)
	m, _ := newTestManager(t, 100)
	w := newTestConvergeWorker(m)
	const poisoned = "0000000000000000000000000000000000000000"
	head := volumeHead{Generation: 4, Digest: poisoned, DownloadURL: srv.URL}

	if got := w.converge(context.Background(), jobRequest("42", head)); got != "unverifiable" {
		t.Fatalf("converge = %q, want unverifiable", got)
	}
	if got := w.converge(context.Background(), jobRequest("42", head)); got != "unverifiable" {
		t.Fatalf("second converge = %q, want unverifiable", got)
	}
	if got := srv.requests.Load(); got != 1 {
		t.Fatalf("downloaded a disproved HEAD %d times, want once", got)
	}

	statusDir := t.TempDir()
	att := mustAllocate(t, m, "vm-next")
	store := NewStore()
	store.Put("ns", "pod", &Entry{VMName: "vm-next", Volume: att, VolumeStatusDir: statusDir})
	r := &Reconciler{Store: store, Volumes: m, Converge: w, ConvergeHeadWaitInterval: time.Millisecond, ConvergeHeadWaitAttempts: 1}
	r.maybeMaterializeVolume(&corev1.Pod{ObjectMeta: metav1.ObjectMeta{
		Namespace: "ns", Name: "pod", Labels: map[string]string{runnerAccountLabel: "42"},
	}})

	staged, err := os.ReadFile(filepath.Join(statusDir, unverifiableHeadFile))
	if err != nil || string(staged) != poisoned {
		t.Fatalf("next job's staged disproof = %q, %v; want %q", staged, err, poisoned)
	}
}

// Bytes spliced from two transfers that do not match say nothing certain about
// the object, so the master is downloaded whole before a mismatch counts.
func TestConvergeRedownloadsAResumedMismatchBeforeBlamingTheHead(t *testing.T) {
	content := []byte("the-real-head-image-bytes")
	srv := serveImage(t, content)
	m, _ := newTestManager(t, 100)
	w := newTestConvergeWorker(m)

	dir := m.ConvergeStagingDir("42", ReservedTuistCacheVolume)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "head-4.sparseimage"), []byte("CORRUPTED"), 0o644); err != nil {
		t.Fatal(err)
	}

	if got := w.converge(context.Background(), jobRequest("42", headFor(content, 4, srv.URL))); got != "converged" {
		t.Fatalf("converge = %q, want converged", got)
	}
	if got := srv.rangeHeaders(); len(got) != 2 || got[0] != "bytes=9-" || got[1] != "" {
		t.Fatalf("Range headers = %q; want a resume, then a whole download", got)
	}
	if d := w.DisprovedDigest("42", ReservedTuistCacheVolume); d != "" {
		t.Fatalf("recorded %q as disproved from a local splice", d)
	}
}

func TestConvergeQueueOrdersJobsAheadOfPrefetches(t *testing.T) {
	m, _ := newTestManager(t, 100)
	w := newTestConvergeWorker(m)
	key := func(account string) masterKey { return masterKey{account: account, volume: ReservedTuistCacheVolume} }
	request := func(account string, generation int, source convergeSource, statusDir string) convergeRequest {
		return convergeRequest{key: key(account), head: volumeHead{Generation: generation}, source: source, statusDir: statusDir}
	}
	order := func() []string {
		w.mu.Lock()
		defer w.mu.Unlock()
		var out []string
		for _, q := range w.queue {
			out = append(out, q.key.account+"@"+strconv.Itoa(q.head.Generation)+"/"+string(q.source))
		}
		return out
	}

	w.Enqueue(request("A", 3, convergeSourcePrefetch, ""))
	w.Enqueue(request("B", 1, convergeSourcePrefetch, ""))
	w.Enqueue(request("C", 2, convergeSourceJob, "status-c"))
	if got := strings.Join(order(), " "); got != "C@2/job A@3/prefetch B@1/prefetch" {
		t.Fatalf("queue = %s", got)
	}

	// An older HEAD never replaces a newer one.
	w.Enqueue(request("A", 2, convergeSourceJob, ""))
	if got := strings.Join(order(), " "); got != "C@2/job A@3/prefetch B@1/prefetch" {
		t.Fatalf("queue after an older HEAD = %s", got)
	}

	// A job's HEAD moves its volume ahead of the prefetches.
	w.Enqueue(request("A", 5, convergeSourceJob, ""))
	if got := strings.Join(order(), " "); got != "C@2/job A@5/job B@1/prefetch" {
		t.Fatalf("queue after a job's HEAD = %s", got)
	}

	// A prefetch of a volume a job queued brings a newer HEAD but keeps the
	// job's standing and status share.
	w.Enqueue(request("C", 6, convergeSourcePrefetch, ""))
	var head convergeRequest
	w.mu.Lock()
	for _, q := range w.queue {
		if q.key.account == "C" {
			head = q
		}
	}
	w.mu.Unlock()
	if head.key.account != "C" || head.head.Generation != 6 || head.source != convergeSourceJob || head.statusDir != "status-c" {
		t.Fatalf("merged request = %+v", head)
	}
}

type stubPrefetch struct {
	masters []PrefetchMaster
	calls   atomic.Int32
}

func (s *stubPrefetch) CacheMasters(context.Context) ([]PrefetchMaster, error) {
	s.calls.Add(1)
	return s.masters, nil
}

// An idle host with nothing queued asks the server what its fleet needs and
// fetches the masters it lacks, at most once per cooldown for each: a master
// admission evicts is not fetched straight back.
func TestConvergePrefetchesTheMastersTheHostLacks(t *testing.T) {
	content := []byte("head-of-42")
	srv := serveImage(t, content)
	m, _ := newTestManager(t, 100)
	seedMasterGen(t, m, "7", masterImageContent("7"), 1)

	head := headFor(content, 4, srv.URL)
	source := &stubPrefetch{masters: []PrefetchMaster{
		{AccountID: 7, Volume: ReservedTuistCacheVolume, Generation: 9, DownloadURL: srv.URL},
		{AccountID: 42, Volume: ReservedTuistCacheVolume, Generation: 4, Digest: head.Digest, ContentDigest: head.ContentDigest, DownloadURL: srv.URL},
		{AccountID: 43, Volume: "../escape", Generation: 1, DownloadURL: srv.URL},
	}}
	now := time.Now()
	w := newTestConvergeWorker(m)
	w.Prefetch = source
	w.now = func() time.Time { return now }

	drain(w)
	if gen, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); gen != 4 {
		t.Fatalf("prefetched generation = %d, want 4", gen)
	}
	if gen, _ := m.MasterGeneration("7", ReservedTuistCacheVolume); gen != 1 {
		t.Fatalf("a resident master was prefetched over (generation %d); jobs keep those current", gen)
	}
	if got := srv.requests.Load(); got != 1 {
		t.Fatalf("downloads = %d, want only the missing master", got)
	}

	// Admission evicts it, and the next poll lists it again.
	if err := os.RemoveAll(m.volumeDir("42", ReservedTuistCacheVolume)); err != nil {
		t.Fatal(err)
	}
	now = now.Add(convergePrefetchInterval)
	drain(w)
	if got := source.calls.Load(); got != 2 {
		t.Fatalf("prefetch polls = %d, want 2", got)
	}
	if got := srv.requests.Load(); got != 1 {
		t.Fatalf("re-downloaded an evicted prefetch inside its cooldown (%d downloads)", got)
	}

	now = now.Add(convergePrefetchCooldown)
	drain(w)
	if gen, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); gen != 4 {
		t.Fatalf("generation after the cooldown = %d, want 4", gen)
	}
}

func TestServerPrefetchAuthenticatesAsTheHost(t *testing.T) {
	var gotAuth, gotPath string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth, gotPath = r.Header.Get("Authorization"), r.URL.Path
		_, _ = w.Write([]byte(`{"masters":[{"account_id":42,"volume":"tuist-cache","generation":4,"digest":"d","content_digest":"c","download_url":"https://objects.example/x"}]}`))
	}))
	defer srv.Close()

	client := fake.NewSimpleClientset()
	client.PrependReactor("create", "selfsubjectreviews", func(k8stesting.Action) (bool, runtime.Object, error) {
		return true, &authenticationv1.SelfSubjectReview{Status: authenticationv1.SelfSubjectReviewStatus{
			UserInfo: authenticationv1.UserInfo{Username: "system:serviceaccount:tuist:tart-kubelet-mac-01"},
		}}, nil
	})
	var mints atomic.Int32
	var mintedFor, audiences string
	client.PrependReactor("create", "serviceaccounts", func(action k8stesting.Action) (bool, runtime.Object, error) {
		if action.GetSubresource() != "token" {
			return false, nil, nil
		}
		mints.Add(1)
		create := action.(k8stesting.CreateActionImpl)
		mintedFor = action.GetNamespace() + "/" + create.Name
		audiences = strings.Join(create.Object.(*authenticationv1.TokenRequest).Spec.Audiences, ",")
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{
			Token:               "host-token",
			ExpirationTimestamp: metav1.NewTime(time.Now().Add(10 * time.Minute)),
		}}, nil
	})

	s := &ServerPrefetch{Client: client}
	if _, err := s.CacheMasters(context.Background()); err != errPrefetchUnavailable {
		t.Fatalf("before any runner Pod: err = %v, want errPrefetchUnavailable", err)
	}

	pod := func(url string) *corev1.Pod {
		return &corev1.Pod{Spec: corev1.PodSpec{Containers: []corev1.Container{{
			Env: []corev1.EnvVar{{Name: runnerDispatchURLEnv, Value: url}},
		}}}}
	}
	s.ObservePod(pod("https://evil.example/somewhere-else"))
	if _, err := s.CacheMasters(context.Background()); err != errPrefetchUnavailable {
		t.Fatalf("a URL that is not the dispatch endpoint was adopted: err = %v", err)
	}
	s.ObservePod(pod(srv.URL + runnerDispatchPath))

	for i := 0; i < 2; i++ {
		masters, err := s.CacheMasters(context.Background())
		if err != nil {
			t.Fatalf("CacheMasters: %v", err)
		}
		if len(masters) != 1 || masters[0].AccountID != 42 || masters[0].Generation != 4 {
			t.Fatalf("masters = %+v", masters)
		}
	}
	if gotPath != cacheMastersPath || gotAuth != "Bearer host-token" {
		t.Fatalf("request = %s with %q", gotPath, gotAuth)
	}
	if mintedFor != "tuist/tart-kubelet-mac-01" || audiences != RunnerHostAudience {
		t.Fatalf("minted for %s with audiences %q", mintedFor, audiences)
	}
	if got := mints.Load(); got != 1 {
		t.Fatalf("minted %d tokens for two calls, want the first reused", got)
	}
}

func TestParseContentRange(t *testing.T) {
	for _, tc := range []struct {
		header      string
		start, size int64
		ok          bool
	}{
		{header: "bytes 100-199/200", start: 100, size: 200, ok: true},
		{header: "bytes */200", size: 200, ok: true},
		{header: "bytes 100-199/*"},
		{header: "items 0-1/2"},
		{header: ""},
	} {
		start, size, ok := parseContentRange(tc.header)
		if start != tc.start || size != tc.size || ok != tc.ok {
			t.Errorf("parseContentRange(%q) = %d, %d, %v", tc.header, start, size, ok)
		}
	}
}
