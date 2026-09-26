package podagent

import (
	"bytes"
	"context"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"errors"
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
	// Unused for longer than convergeEvictIdleAfter, so a job's download may
	// evict them.
	base := time.Now().Add(-convergeEvictIdleAfter - time.Hour)
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
// the object does not reproduce it, so the disproof is relayed by the next job
// dispatched with that same HEAD, whose promote can retire it. The host does
// not download a HEAD it has already disproved.
func TestConvergeRelaysADisproofWithTheNextJobOnTheSameHead(t *testing.T) {
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
	stageHead(t, statusDir, head)
	r := &Reconciler{Volumes: m, Converge: w, ConvergeHeadWaitInterval: time.Millisecond, ConvergeHeadWaitAttempts: 1}
	r.queueConvergence("vm-next", statusDir, ReservedTuistCacheVolume, "42")

	staged, err := os.ReadFile(filepath.Join(statusDir, unverifiableHeadFile))
	if err != nil || string(staged) != poisoned {
		t.Fatalf("next job's staged disproof = %q, %v; want %q", staged, err, poisoned)
	}
}

// Two objects can share an inventory digest and differ in content, and the
// server keys them apart. A disproof of one must not reject the other: after a
// corrupt HEAD is replaced by a valid one with the same inventory, the host
// downloads the replacement, and a job dispatched with it relays nothing.
func TestConvergeScopesADisproofToTheObject(t *testing.T) {
	valid := []byte("the-valid-replacement-image")
	srv := serveImage(t, valid)
	m, _ := newTestManager(t, 100)
	w := newTestConvergeWorker(m)

	replacement := headFor(valid, 5, srv.URL)
	corrupt := replacement
	corrupt.Generation = 4
	corrupt.ContentDigest = strings.Repeat("0", 64)
	if got := w.converge(context.Background(), jobRequest("42", corrupt)); got != "unverifiable" {
		t.Fatalf("converge of the corrupt HEAD = %q, want unverifiable", got)
	}

	statusDir := t.TempDir()
	stageHead(t, statusDir, replacement)
	r := &Reconciler{Volumes: m, Converge: w, ConvergeHeadWaitInterval: time.Millisecond, ConvergeHeadWaitAttempts: 1}
	r.queueConvergence("vm-next", statusDir, ReservedTuistCacheVolume, "42")
	if staged, err := os.ReadFile(filepath.Join(statusDir, unverifiableHeadFile)); err == nil {
		t.Fatalf("a job on the valid replacement relayed the old disproof %q, which could retire it", staged)
	}

	drain(w)
	if gen, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); gen != 5 {
		t.Fatalf("generation = %d; the valid replacement sharing the inventory digest must converge", gen)
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
	if w.disproven(masterKey{account: "42", volume: ReservedTuistCacheVolume}, headFor(content, 4, srv.URL)) {
		t.Fatal("recorded a local splice as a disproof of the HEAD")
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

type unavailableUntil struct {
	ready atomic.Bool
	calls atomic.Int32
}

func (s *unavailableUntil) CacheMasters(context.Context) ([]PrefetchMaster, error) {
	s.calls.Add(1)
	if !s.ready.Load() {
		return nil, errPrefetchUnavailable
	}
	return nil, nil
}

// Every start polls before any runner Pod has said where the server is. That
// must not cost the host a whole prefetch interval.
func TestConvergePrefetchesAsSoonAsTheServerIsKnown(t *testing.T) {
	m, _ := newTestManager(t, 100)
	source := &unavailableUntil{}
	w := newTestConvergeWorker(m)
	w.Prefetch = source

	drain(w)
	source.ready.Store(true)
	drain(w)
	if got := source.calls.Load(); got != 2 {
		t.Fatalf("prefetch polls = %d; the first poll after the server became known must not wait an interval", got)
	}
}

// heldImageServer sends the first MiB of content, then holds the transfer open
// until released, so a test can admit jobs while a download is in flight.
func heldImageServer(t *testing.T, content []byte) (url string, started <-chan struct{}, release func()) {
	t.Helper()
	first := make(chan struct{})
	held := make(chan struct{})
	var once sync.Once
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", strconv.Itoa(len(content)))
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(content[:1<<20])
		w.(http.Flusher).Flush()
		once.Do(func() { close(first) })
		select {
		case <-held:
			_, _ = w.Write(content[1<<20:])
		case <-r.Context().Done():
		}
	}))
	var releaseOnce sync.Once
	t.Cleanup(func() {
		releaseOnce.Do(func() { close(held) })
		srv.Close()
	})
	return srv.URL, first, func() { releaseOnce.Do(func() { close(held) }) }
}

// awaitDownloading waits until the download for account has reserved its space
// and written into its partial image, so jobs admitted next see it in flight.
func awaitDownloading(t *testing.T, m *VolumeManager, account string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		matches, _ := filepath.Glob(filepath.Join(m.ConvergeStagingDir(account, ReservedTuistCacheVolume), "head-*.sparseimage"))
		if len(matches) == 1 {
			if info, err := os.Stat(matches[0]); err == nil && info.Size() >= 1<<20 {
				return
			}
		}
		if time.Now().After(deadline) {
			t.Fatal("the download never started writing")
		}
		time.Sleep(time.Millisecond)
	}
}

// A job admitted while a download runs is promised space the download has not
// written yet. Jobs outrank downloads: when a job and the rest of a prefetch
// do not both fit, the job is admitted and the prefetch gives its space back.
func TestConvergePrefetchGivesWayToAJobAdmittedMidDownload(t *testing.T) {
	content := bytes.Repeat([]byte("p"), 48<<20)
	url, started, release := heldImageServer(t, content)
	root := t.TempDir()
	// 2 GiB + 32 MiB free: two 1 GiB branches fit, and one fits beside the
	// rest of the download, but two do not.
	m := NewVolumeManager(root, 1, &fakeBackend{totalBytes: 2*gib + 32<<20, perMaster: gib, root: root})
	w := newTestConvergeWorker(m)
	w.AlongsideJobs = true
	w.busyBytesPerSec = 1 << 40
	req := jobRequest("42", headFor(content, 4, url))
	req.source = convergeSourcePrefetch

	result := make(chan string, 1)
	go func() { result <- w.converge(context.Background(), req) }()
	<-started
	awaitDownloading(t, m, "42")

	startJob(t, m, "vm-1", "7")
	select {
	case got := <-result:
		t.Fatalf("the download stopped (%q) for a job that fit beside it", got)
	case <-time.After(50 * time.Millisecond):
	}
	startJob(t, m, "vm-2", "8")
	release()

	if got := <-result; got != "displaced" {
		t.Fatalf("converge = %q; want the prefetch displaced by the job admitted into its space", got)
	}
	if _, err := os.Stat(m.ConvergeStagingDir("42", ReservedTuistCacheVolume)); !os.IsNotExist(err) {
		t.Fatalf("a displaced download kept its partial image: %v", err)
	}
}

// A job's own download may evict for its space, as admission does, so a job
// admitted mid-download makes room for both by evicting LRU masters rather than
// dropping a download of a volume that has run here.
func TestConvergeJobDownloadKeepsItsSpaceByEvicting(t *testing.T) {
	content := bytes.Repeat([]byte("j"), 48<<20)
	url, started, release := heldImageServer(t, content)
	root := t.TempDir()
	m := NewVolumeManager(root, 1, &fakeBackend{totalBytes: 3*gib + 32<<20, perMaster: gib, root: root})
	seedMasterGen(t, m, "9", masterImageContent("9"), 1)
	ageMaster(t, m, "9", convergeEvictIdleAfter+time.Hour)
	w := newTestConvergeWorker(m)
	w.AlongsideJobs = true
	w.busyBytesPerSec = 1 << 40

	result := make(chan string, 1)
	go func() { result <- w.converge(context.Background(), jobRequest("42", headFor(content, 4, url))) }()
	<-started
	awaitDownloading(t, m, "42")

	startJob(t, m, "vm-1", "7")
	startJob(t, m, "vm-2", "8")
	release()

	if got := <-result; got != "converged" {
		t.Fatalf("converge = %q, want converged", got)
	}
	if masterExists(m, "9") {
		t.Fatal("admission did not evict the idle master to keep both jobs and the download")
	}
}

// m2L is a runner-cache volume at the production M2-L numbers: 80 GiB with a
// 30 GiB cap, so the evictor keeps 36 GiB free, and masters of 25 GiB like the
// largest compacted masters in production.
func m2L(t *testing.T) (*VolumeManager, *fakeBackend) {
	t.Helper()
	root := t.TempDir()
	be := &fakeBackend{totalBytes: 80 * gib, perMaster: 25 * gib, root: root}
	return NewVolumeManager(root, 30, be), be
}

func stagePartial(t *testing.T, m *VolumeManager, account string) {
	t.Helper()
	dir := m.ConvergeStagingDir(account, ReservedTuistCacheVolume)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "head-2.sparseimage"), []byte("partial"), 0o644); err != nil {
		t.Fatal(err)
	}
}

// Refreshing a resident master holds both images while it downloads, but the
// install gives the old one's space back. Requiring the headroom on top of both
// would refuse every refresh of a master over 22 GiB on an M2-L, leaving the
// stale masters this worker exists to fix with no way to be refreshed.
func TestConvergeRefreshesALargeResidentMasterOnAnM2L(t *testing.T) {
	key := masterKey{account: "42", volume: ReservedTuistCacheVolume}
	noop := func(error) {}

	m, _ := m2L(t)
	seedMasterGen(t, m, "42", masterImageContent("42"), 1)
	r, err := m.PrepareConvergeSpace(key, 25*gib, 25*gib, true, noop)
	if err != nil {
		t.Fatalf("refresh of a 25 GiB master on an M2-L: %v", err)
	}
	r.Release()
	if !masterExists(m, "42") {
		t.Fatal("the refresh evicted the master it replaces before the new one was verified")
	}

	cold, _ := m2L(t)
	if r, err := cold.PrepareConvergeSpace(key, 25*gib, 25*gib, true, noop); err != nil {
		t.Fatalf("a cold M2-L refused a 25 GiB master: %v", err)
	} else {
		r.Release()
	}

	// While a job holds a branch, the branch may share the master's blocks, so
	// the install frees nothing to count on.
	busy, _ := m2L(t)
	seedMasterGen(t, busy, "42", masterImageContent("42"), 1)
	startJob(t, busy, "vm-job", "42")
	if _, err := busy.PrepareConvergeSpace(key, 25*gib, 25*gib, true, noop); !errors.Is(err, errNoRoomToConverge) {
		t.Fatalf("err = %v; with a job cloned from the master, the refresh cannot count on its space", err)
	}
}

// Mid-refresh the volume sits below the watermark by the space the install is
// about to return. The evictor must not drop other accounts' masters for it.
func TestEvictorLeavesMastersAloneForAnInFlightRefresh(t *testing.T) {
	root := t.TempDir()
	be := &fakeBackend{totalBytes: 90 * gib, perMaster: 25 * gib, perStagingFile: 25 * gib, root: root}
	m := NewVolumeManager(root, 30, be)
	seedMasterGen(t, m, "42", masterImageContent("42"), 1)
	seedMasterGen(t, m, "7", masterImageContent("7"), 1)

	r, err := m.PrepareConvergeSpace(masterKey{account: "42", volume: ReservedTuistCacheVolume}, 25*gib, 25*gib, true, func(error) {})
	if err != nil {
		t.Fatalf("PrepareConvergeSpace: %v", err)
	}
	defer r.Release()
	stagePartial(t, m, "42")

	if evicted, err := m.EvictToWatermark(); err != nil || evicted != 0 {
		t.Fatalf("EvictToWatermark evicted %d (err %v) for space the refresh returns on install", evicted, err)
	}
	if !masterExists(m, "7") {
		t.Fatal("another account's master was evicted mid-refresh")
	}
}

// A job outranks a partial download: before admission declines a job, it drops
// the partial and takes the space. A refresh can leave the volume below the
// watermark, so on an M2 the paused partial is often there when a job lands.
func TestAdmissionDropsAPartialDownloadBeforeDecliningAJob(t *testing.T) {
	root := t.TempDir()
	be := &fakeBackend{totalBytes: 50 * gib, perMaster: 25 * gib, perStagingFile: 30 * gib, root: root}
	m := NewVolumeManager(root, 30, be)
	stagePartial(t, m, "42")

	att := mustAllocate(t, m, "vm-job")
	if _, _, err := m.Materialize(att, "7"); err != nil {
		t.Fatalf("Materialize: %v; the job must take the partial download's space", err)
	}
	if _, err := os.Stat(filepath.Join(root, convergeDirName)); !os.IsNotExist(err) {
		t.Fatalf("the partial download is still on disk: %v", err)
	}
}

// A master a generation or two behind still starts a job almost fully warm, so
// a job-queued refresh leaves it in place until it falls further behind or ages
// out. Before this, M2 hosts re-downloaded a 23-25 GiB master after nearly
// every job of an account whose HEAD moves every couple of hours.
func TestConvergeLeavesARecentMasterInPlace(t *testing.T) {
	content := []byte("head-of-42")
	now := time.Now()
	for _, tc := range []struct {
		name       string
		generation int
		installed  time.Duration
		want       string
	}{
		{name: "two generations behind, installed recently", generation: 7, installed: time.Hour, want: "recent"},
		{name: "three generations behind", generation: 8, installed: time.Hour, want: "converged"},
		{name: "one generation behind, installed long ago", generation: 6, installed: 13 * time.Hour, want: "converged"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			srv := serveImage(t, content)
			m, _ := newTestManager(t, 100)
			seedMasterGen(t, m, "42", masterImageContent("42"), 5)
			installedAt := now.Add(-tc.installed)
			if err := os.Chtimes(m.masterGenerationPath("42", ReservedTuistCacheVolume), installedAt, installedAt); err != nil {
				t.Fatal(err)
			}
			w := newTestConvergeWorker(m)
			w.now = func() time.Time { return now }

			if got := w.converge(context.Background(), jobRequest("42", headFor(content, tc.generation, srv.URL))); got != tc.want {
				t.Fatalf("converge = %q, want %q", got, tc.want)
			}
			if tc.want == "recent" && srv.requests.Load() != 0 {
				t.Fatal("downloaded a master it left in place")
			}
		})
	}
}

// ageMaster makes the account's master look unused for age.
func ageMaster(t *testing.T, m *VolumeManager, account string, age time.Duration) {
	t.Helper()
	stamp := time.Now().Add(-age)
	if err := os.Chtimes(m.masterImage(account, ReservedTuistCacheVolume), stamp, stamp); err != nil {
		t.Fatal(err)
	}
}

// On an M2-L, a 25 GiB master and a 22.5 GiB one do not fit beside a job's
// headroom. Each download used to evict the other: the account whose master was
// pushed out landed its next job cold and downloaded it all again, which in
// turn pushed the first one out. A convergence download may now only evict a
// master unused for convergeEvictIdleAfter.
func TestConvergeDoesNotEvictAMasterInActiveUse(t *testing.T) {
	carousell := masterKey{account: "4094", volume: ReservedTuistCacheVolume}
	noop := func(error) {}

	m, _ := m2L(t)
	seedMasterGen(t, m, "3", masterImageContent("3"), 1)
	ageMaster(t, m, "3", time.Hour)
	if _, err := m.PrepareConvergeSpace(carousell, 22*gib+gib/2, 22*gib+gib/2, true, noop); !errors.Is(err, errNoRoomBesideActiveMasters) {
		t.Fatalf("err = %v; a download must not evict a master used an hour ago", err)
	}
	if !masterExists(m, "3") {
		t.Fatal("the master in active use was evicted")
	}

	ageMaster(t, m, "3", convergeEvictIdleAfter+time.Hour)
	r, err := m.PrepareConvergeSpace(carousell, 22*gib+gib/2, 22*gib+gib/2, true, noop)
	if err != nil {
		t.Fatalf("PrepareConvergeSpace beside an idle master: %v", err)
	}
	r.Release()
	if masterExists(m, "3") {
		t.Fatal("the idle master was not evicted for the download")
	}
}

func TestConvergeReportsActiveMastersInTheWay(t *testing.T) {
	content := []byte("head-of-4094")
	srv := serveImage(t, content)
	root := t.TempDir()
	// 60 GiB with a 30 GiB cap keeps 36 GiB free; one 25 GiB master leaves 35.
	m := NewVolumeManager(root, 30, &fakeBackend{totalBytes: 60 * gib, perMaster: 25 * gib, root: root})
	seedMasterGen(t, m, "3", masterImageContent("3"), 1)
	messages := captureLogs(t)

	w := newTestConvergeWorker(m)
	if got := w.converge(context.Background(), jobRequest("4094", headFor(content, 2, srv.URL))); got != "active_masters" {
		t.Fatalf("converge = %q, want active_masters", got)
	}
	if !masterExists(m, "3") {
		t.Fatal("the master in active use was evicted")
	}
	for _, msg := range messages() {
		if strings.Contains(msg, "without evicting one used in the last 12 hours") {
			return
		}
	}
	t.Fatalf("no log line explains the decline; got %v", messages())
}

// A job admitted mid-download may still evict what it needs for itself, but
// keeping the download's bytes as well may only evict what the download could:
// with only an active master to evict, the download gives way instead.
func TestAdmissionDisplacesADownloadRatherThanEvictAnActiveMaster(t *testing.T) {
	content := bytes.Repeat([]byte("a"), 48<<20)
	url, started, release := heldImageServer(t, content)
	root := t.TempDir()
	m := NewVolumeManager(root, 1, &fakeBackend{totalBytes: 3*gib + 32<<20, perMaster: gib, root: root})
	seedMasterGen(t, m, "9", masterImageContent("9"), 1)
	w := newTestConvergeWorker(m)
	w.AlongsideJobs = true
	w.busyBytesPerSec = 1 << 40

	result := make(chan string, 1)
	go func() { result <- w.converge(context.Background(), jobRequest("42", headFor(content, 4, url))) }()
	<-started
	awaitDownloading(t, m, "42")

	startJob(t, m, "vm-1", "7")
	startJob(t, m, "vm-2", "8")
	release()

	if got := <-result; got != "displaced" {
		t.Fatalf("converge = %q; want the download displaced rather than the active master evicted", got)
	}
	if !masterExists(m, "9") {
		t.Fatal("an active master was evicted to keep a download")
	}
}
