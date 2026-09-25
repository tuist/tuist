package podagent

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// convergeSource is why a HEAD was queued for this host.
type convergeSource string

const (
	// convergeSourceJob: a job for the volume ran on this host and relayed the
	// HEAD it was dispatched with. Demand is proven, so the download may evict
	// LRU masters for its space, as admission does for a job.
	convergeSourceJob convergeSource = "job"
	// convergeSourcePrefetch: the server listed the HEAD for this host's fleet
	// (queued or recent jobs) and the host holds no master for the volume.
	// Speculative, so it only uses space that is already free.
	convergeSourcePrefetch convergeSource = "prefetch"
)

const (
	// convergePollInterval is how often the worker re-checks whether it may
	// download, and how often a running download checks whether it must yield.
	convergePollInterval = 15 * time.Second
	// convergePrefetchInterval is how often an idle worker asks the server which
	// masters this host should hold.
	convergePrefetchInterval = 10 * time.Minute
	// convergePrefetchCooldown bounds how often one volume is prefetched. A
	// prefetched master that admission later evicts would otherwise be fetched
	// again on the next idle poll, and a 20+ GiB master churned like that costs
	// far more egress than the cold jobs it saves.
	convergePrefetchCooldown = 6 * time.Hour
	// convergeRequestMaxAge drops a queued HEAD before its presigned download URL
	// can expire (the server signs them for six hours). A job for the volume, or
	// the next prefetch poll, queues a fresh one.
	convergeRequestMaxAge = 5 * time.Hour
	// convergeStallTimeout abandons a download attempt that receives nothing for
	// this long. It replaces a single deadline on the whole transfer, which had
	// to choose between killing a healthy download of a large master and waiting
	// out a dead one.
	convergeStallTimeout = 2 * time.Minute
	// convergeDownloadAttempts / convergeRetryBackoff bound retries of a download
	// that fails partway. Each retry resumes where the last one stopped.
	convergeDownloadAttempts = 5
	convergeRetryBackoff     = 30 * time.Second
	// convergeBusyBytesPerSecond caps a download that runs while a job is running
	// on the host, so the transfer never takes the job's disk and network.
	convergeBusyBytesPerSecond = 50 << 20
	// convergeAlongsideJobsHeadroomBytes is the RAM a host must have beyond what
	// it promises its guests before a download may run beside a job. Below it the
	// guests are backed by swap and the host has nothing to give the transfer.
	convergeAlongsideJobsHeadroomBytes = 8 << 30
)

// ConvergeAlongsideJobs reports whether a host may download a master while a
// job runs on it: only when its installed RAM exceeds the memory it advertises
// to the scheduler by convergeAlongsideJobsHeadroomBytes. A host without that
// headroom converges only while no job runs, and a download in progress yields
// to a job that lands.
func ConvergeAlongsideJobs(physicalBytes uint64, advertisedMemoryMB int) bool {
	if advertisedMemoryMB < 0 {
		return false
	}
	advertised := uint64(advertisedMemoryMB) << 20
	return physicalBytes > advertised && physicalBytes-advertised >= convergeAlongsideJobsHeadroomBytes
}

// errConvergeYielded: a job landed on a host that does not download beside
// jobs. The partial image is kept, and the download resumes when the host is
// idle again.
var errConvergeYielded = errors.New("convergence yielded to a job")

var errConvergeStalled = errors.New("master download stalled")

// permanentDownloadError is a download failure retrying cannot fix: the URL is
// refused or gone, or the host has no room for the master.
type permanentDownloadError struct{ err error }

func (e permanentDownloadError) Error() string { return e.err.Error() }
func (e permanentDownloadError) Unwrap() error { return e.err }

func permanent(err error) error { return permanentDownloadError{err: err} }

type convergeRequest struct {
	key    masterKey
	head   volumeHead
	source convergeSource
	// queuedAt is when the HEAD, and so its presigned URL, was obtained.
	queuedAt time.Time
	// statusDir is the status share of the job that relayed the HEAD, where a
	// disproved digest is staged while that job still runs. Empty for a prefetch.
	statusDir string
}

// ConvergeWorker fast-forwards this host's masters to their volumes' HEADs off
// every job's critical path. It downloads one master at a time. On a host
// without the memory to download beside a job it runs only while no job does,
// and a job that lands stops the download, which resumes from the bytes already
// on disk once the host is idle again. When idle and out of work, it asks the
// server which masters this host's fleet is likely to need and prefetches the
// ones it does not hold, so the first job for a volume on this host can start
// warm too.
type ConvergeWorker struct {
	Volumes *VolumeManager
	// AlongsideJobs lets downloads run while jobs do, throttled to
	// convergeBusyBytesPerSecond. See ConvergeAlongsideJobs.
	AlongsideJobs bool
	// Prefetch lists the masters the server wants this host to hold. Nil
	// disables prefetching.
	Prefetch PrefetchSource

	// Zero values use the package defaults; injectable so tests don't wait real
	// minutes.
	pollInterval     time.Duration
	prefetchInterval time.Duration
	stallTimeout     time.Duration
	retryBackoff     time.Duration
	busyBytesPerSec  float64
	client           *http.Client
	now              func() time.Time

	mu sync.Mutex
	// queue holds at most one request per volume, job-sourced ahead of prefetch.
	queue []convergeRequest
	// disproved holds, per volume, the HEAD this host downloaded and found the
	// stored object does not reproduce, identified by generation and both
	// digests (see sameObject). It is relayed by the next job dispatched with
	// that same HEAD, whose promote lets the server retire it; the job that
	// relayed the HEAD has usually finished by the time the download runs. A
	// newer HEAD for the volume makes it stale.
	disproved map[masterKey]volumeHead
	// prefetchedAt is when each volume was last prefetched.
	prefetchedAt map[masterKey]time.Time
	lastPrefetch time.Time
	wake         chan struct{}
}

// NewConvergeWorker builds a worker for the volumes.
func NewConvergeWorker(volumes *VolumeManager, alongsideJobs bool, prefetch PrefetchSource) *ConvergeWorker {
	return &ConvergeWorker{Volumes: volumes, AlongsideJobs: alongsideJobs, Prefetch: prefetch}
}

func (w *ConvergeWorker) clock() time.Time {
	if w.now != nil {
		return w.now()
	}
	return time.Now()
}

func (w *ConvergeWorker) poll() time.Duration {
	if w.pollInterval > 0 {
		return w.pollInterval
	}
	return convergePollInterval
}

func (w *ConvergeWorker) wakeChan() chan struct{} {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.wake == nil {
		w.wake = make(chan struct{}, 1)
	}
	return w.wake
}

// mayDownload reports whether a download may run now.
func (w *ConvergeWorker) mayDownload() bool {
	return w.AlongsideJobs || w.Volumes.jobsRunning() == 0
}

// ObservePod lets the prefetch source learn where the server is from the runner
// Pods this host runs.
func (w *ConvergeWorker) ObservePod(pod *corev1.Pod) {
	if w == nil {
		return
	}
	if observer, ok := w.Prefetch.(interface{ ObservePod(*corev1.Pod) }); ok {
		observer.ObservePod(pod)
	}
}

// Enqueue queues a HEAD for the volume, replacing any older one already queued.
// A job-sourced request keeps its place ahead of prefetches, and a prefetch for
// a volume a job already queued inherits nothing but a newer HEAD.
func (w *ConvergeWorker) Enqueue(req convergeRequest) {
	if w == nil {
		return
	}
	if req.queuedAt.IsZero() {
		req.queuedAt = w.clock()
	}
	w.mu.Lock()
	for i, queued := range w.queue {
		if queued.key != req.key {
			continue
		}
		if req.head.Generation < queued.head.Generation {
			w.mu.Unlock()
			return
		}
		if queued.source == convergeSourceJob && req.source != convergeSourceJob {
			req.source = convergeSourceJob
			req.statusDir = queued.statusDir
		}
		w.queue = append(w.queue[:i], w.queue[i+1:]...)
		break
	}
	w.insertLocked(req)
	w.mu.Unlock()
	w.signal()
}

func (w *ConvergeWorker) insertLocked(req convergeRequest) {
	if req.source != convergeSourceJob {
		w.queue = append(w.queue, req)
		return
	}
	at := 0
	for at < len(w.queue) && w.queue[at].source == convergeSourceJob {
		at++
	}
	w.queue = append(w.queue, convergeRequest{})
	copy(w.queue[at+1:], w.queue[at:])
	w.queue[at] = req
}

func (w *ConvergeWorker) signal() {
	select {
	case w.wakeChan() <- struct{}{}:
	default:
	}
}

// pop takes the next request whose presigned URL has not aged out.
func (w *ConvergeWorker) pop() (convergeRequest, bool) {
	w.mu.Lock()
	defer w.mu.Unlock()
	for len(w.queue) > 0 {
		req := w.queue[0]
		w.queue = w.queue[1:]
		if w.clock().Sub(req.queuedAt) > convergeRequestMaxAge {
			log.Log.WithName("volume").Info("converge: dropping a queued HEAD whose download URL may have expired",
				"account", req.key.account, "volume", req.key.volume, "generation", req.head.Generation, "source", req.source)
			_ = os.RemoveAll(w.Volumes.ConvergeStagingDir(req.key.account, req.key.volume))
			RecordVolumeConverge(req.source, "expired")
			continue
		}
		return req, true
	}
	return convergeRequest{}, false
}

// requeue puts back a request that yielded, unless a newer HEAD for its volume
// was queued meanwhile.
func (w *ConvergeWorker) requeue(req convergeRequest) {
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, queued := range w.queue {
		if queued.key == req.key {
			return
		}
	}
	if req.source == convergeSourceJob {
		w.queue = append([]convergeRequest{req}, w.queue...)
		return
	}
	at := 0
	for at < len(w.queue) && w.queue[at].source == convergeSourceJob {
		at++
	}
	w.queue = append(w.queue, convergeRequest{})
	copy(w.queue[at+1:], w.queue[at:])
	w.queue[at] = req
}

// sameObject reports whether two HEADs name the same stored object. The
// inventory digest alone does not: two images can hold the same entries with
// different bytes, and the server keys their objects apart by content digest.
func sameObject(a, b volumeHead) bool {
	return a.Generation == b.Generation && a.Digest == b.Digest && a.ContentDigest == b.ContentDigest
}

// disprovenLocked reports whether head is the object this host disproved for
// the volume, and forgets evidence about an older HEAD, which says nothing
// about this one.
func (w *ConvergeWorker) disprovenLocked(key masterKey, head volumeHead) bool {
	disproved, ok := w.disproved[key]
	if !ok {
		return false
	}
	if disproved.Generation < head.Generation {
		delete(w.disproved, key)
		return false
	}
	return sameObject(disproved, head)
}

func (w *ConvergeWorker) disproven(key masterKey, head volumeHead) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.disprovenLocked(key, head)
}

// RelayDisproof stages the disproof for a job dispatched with the very HEAD this
// host found unverifiable, so the job's promote can retire it. A job dispatched
// with any other HEAD relays nothing.
func (w *ConvergeWorker) RelayDisproof(key masterKey, head volumeHead, statusDir string) {
	if w == nil || !w.disproven(key, head) {
		return
	}
	stageUnverifiableHead(statusDir, head.Digest)
}

func (w *ConvergeWorker) setDisproved(key masterKey, head volumeHead) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.disproved == nil {
		w.disproved = map[masterKey]volumeHead{}
	}
	w.disproved[key] = head
}

func (w *ConvergeWorker) clearDisproved(key masterKey) {
	w.mu.Lock()
	defer w.mu.Unlock()
	delete(w.disproved, key)
}

// Start implements manager.Runnable.
func (w *ConvergeWorker) Start(ctx context.Context) error {
	if w.Volumes == nil || !w.Volumes.Enabled() {
		return nil
	}
	wake := w.wakeChan()
	t := time.NewTicker(w.poll())
	defer t.Stop()
	for {
		for w.step(ctx) {
		}
		select {
		case <-ctx.Done():
			return nil
		case <-wake:
		case <-t.C:
		}
	}
}

// step does one unit of work and reports whether there may be more to do now.
func (w *ConvergeWorker) step(ctx context.Context) bool {
	if ctx.Err() != nil || !w.mayDownload() {
		return false
	}
	req, ok := w.pop()
	if !ok {
		return w.refreshPrefetch(ctx)
	}
	result := w.converge(ctx, req)
	RecordVolumeConverge(req.source, result)
	if result == "yielded" {
		w.requeue(req)
		return false
	}
	return true
}

// refreshPrefetch asks the server which masters this host should hold, at most
// once per prefetch interval, and queues the ones it lacks. Reports whether it
// queued anything.
func (w *ConvergeWorker) refreshPrefetch(ctx context.Context) bool {
	if w.Prefetch == nil {
		return false
	}
	interval := w.prefetchInterval
	if interval <= 0 {
		interval = convergePrefetchInterval
	}
	now := w.clock()
	w.mu.Lock()
	due := w.lastPrefetch.IsZero() || now.Sub(w.lastPrefetch) >= interval
	if due {
		w.lastPrefetch = now
	}
	w.mu.Unlock()
	if !due {
		return false
	}

	logger := log.Log.WithName("volume")
	masters, err := w.Prefetch.CacheMasters(ctx)
	if errors.Is(err, errPrefetchUnavailable) {
		// Not a poll: no runner Pod has said where the server is yet, which is
		// every start. Ask again as soon as one has.
		w.mu.Lock()
		w.lastPrefetch = time.Time{}
		w.mu.Unlock()
		return false
	}
	if err != nil {
		logger.Error(err, "converge: list the masters to prefetch")
		return false
	}
	queued := 0
	for _, master := range masters {
		account := strconv.FormatInt(master.AccountID, 10)
		if master.AccountID <= 0 || !isVolumeName(master.Volume) || master.Generation <= 0 || master.DownloadURL == "" {
			continue
		}
		key := masterKey{account: account, volume: master.Volume}
		if w.Volumes.HasMaster(key.account, key.volume) || w.prefetchCoolingDown(key, now) {
			continue
		}
		w.Enqueue(convergeRequest{
			key: key,
			head: volumeHead{
				Generation:    master.Generation,
				Digest:        master.Digest,
				ContentDigest: master.ContentDigest,
				DownloadURL:   master.DownloadURL,
			},
			source:   convergeSourcePrefetch,
			queuedAt: now,
		})
		queued++
	}
	return queued > 0
}

func (w *ConvergeWorker) prefetchCoolingDown(key masterKey, now time.Time) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	at, ok := w.prefetchedAt[key]
	return ok && now.Sub(at) < convergePrefetchCooldown
}

func (w *ConvergeWorker) markPrefetched(key masterKey) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.prefetchedAt == nil {
		w.prefetchedAt = map[masterKey]time.Time{}
	}
	w.prefetchedAt[key] = w.clock()
}

// converge fast-forwards the volume's master to the request's HEAD and returns
// the outcome for the converge metric. Every path out of it logs why, because
// convergence is the only way a host holding no master for a volume obtains one.
func (w *ConvergeWorker) converge(ctx context.Context, req convergeRequest) string {
	logger := log.Log.WithName("volume").WithValues(
		"account", req.key.account, "volume", req.key.volume, "generation", req.head.Generation, "source", req.source)
	key, head := req.key, req.head

	// The generation is monotonic (the server only ever fast-forwards it), so a
	// local generation >= the HEAD's means this host already holds that HEAD, or
	// its own newer promote.
	if local, err := w.Volumes.MasterGeneration(key.account, key.volume); err == nil && local >= head.Generation {
		logger.Info("converge: host already at or past the HEAD; nothing to adopt", "local_generation", local)
		_ = os.RemoveAll(w.Volumes.ConvergeStagingDir(key.account, key.volume))
		return "current"
	}
	if w.disproven(key, head) {
		logger.Info("converge: this host already found this HEAD's object does not reproduce its digests; not downloading it again",
			"digest", head.Digest, "content_digest", head.ContentDigest)
		return "unverifiable"
	}
	if req.source == convergeSourcePrefetch {
		if w.Volumes.HasMaster(key.account, key.volume) {
			logger.Info("converge: a job made this volume resident before its prefetch ran; skipping")
			return "current"
		}
		w.markPrefetched(key)
	}

	dir := w.Volumes.ConvergeStagingDir(key.account, key.volume)
	image := filepath.Join(dir, "head-"+strconv.Itoa(head.Generation)+".sparseimage")
	if err := clearStagingExcept(dir, image); err != nil {
		logger.Error(err, "converge: prepare staging")
		return "failed"
	}

	started := w.clock()
	var transfer downloadStats
	defer func() { RecordVolumeConvergeBytes(req.source, transfer.bytes) }()

	// A resumed download is spliced from two transfers. A mismatch in one says
	// nothing certain about the object, so it is downloaded once more whole
	// before any mismatch counts as proof against the HEAD.
	for round := 0; ; round++ {
		resumed, stats, err := w.download(ctx, req, image)
		transfer.bytes += stats.bytes
		transfer.attempts += stats.attempts
		switch {
		case errors.Is(err, errConvergeYielded):
			logger.Info("converge: a job landed on this host; pausing the download until it is idle", "bytes", transfer.bytes)
			return "yielded"
		case errors.Is(err, errConvergeDisplaced):
			logger.Info("converge: a job was admitted into the space this download reserved; dropping it", "bytes", transfer.bytes)
			_ = os.RemoveAll(dir)
			return "displaced"
		case errors.Is(err, errMasterTooLargeToKeep):
			logger.Info("converge: master is larger than this host can keep beside its watermark; not downloading it")
			_ = os.RemoveAll(dir)
			return "too_large"
		case errors.Is(err, errNoRoomToConverge):
			logger.Info("converge: no room on the runner-cache volume for this master; not downloading it")
			_ = os.RemoveAll(dir)
			return "no_room"
		case err != nil:
			logger.Error(err, "converge: download master image", "bytes", transfer.bytes, "attempts", transfer.attempts)
			_ = os.RemoveAll(dir)
			return "failed"
		}

		verified, disproved := w.verify(logger, head, image)
		if verified {
			break
		}
		if disproved && resumed && round == 0 {
			logger.Info("converge: a resumed download does not match the HEAD; downloading it whole before trusting that")
			_ = os.Remove(image)
			continue
		}
		_ = os.RemoveAll(dir)
		if !disproved {
			return "failed"
		}
		w.setDisproved(key, head)
		stageUnverifiableHead(req.statusDir, head.Digest)
		return "unverifiable"
	}

	// Adopt the HEAD wholesale: a plain generation-gated whole-image replace. HEAD
	// is a monotonic fast-forward lineage, so replacing a behind master with it
	// strands nothing.
	installed, err := w.Volumes.InstallMaster(key.account, key.volume, image, head.Generation)
	_ = os.RemoveAll(dir)
	if err != nil {
		logger.Error(err, "converge: install master")
		return "failed"
	}
	if !installed {
		// A promote moved the master past this HEAD while the download ran, so
		// the generation gate declined the swap.
		logger.Info("converge: master moved past this HEAD mid-download; discarding")
		return "current"
	}
	w.clearDisproved(key)
	RecordVolumeConverged()
	seconds := w.clock().Sub(started).Seconds()
	RecordVolumeConvergeSeconds(req.source, seconds)
	// Bytes and time of this pass only: a download that yielded earlier resumed
	// with the bytes it already had.
	values := []any{"bytes", transfer.bytes, "seconds", int64(seconds), "attempts", transfer.attempts}
	if seconds > 0 {
		values = append(values, "mib_per_second", float64(transfer.bytes)/(1<<20)/seconds)
	}
	logger.Info("converged master to HEAD", values...)
	return "converged"
}

// verify checks the downloaded image against the HEAD's content digest and
// then its inventory digest. disproved is true only when a digest was measured
// and differs, which is proof about the object, reproducible on every host. A
// failure to measure is a local fault and says nothing about it.
func (w *ConvergeWorker) verify(logger logr.Logger, head volumeHead, image string) (verified, disproved bool) {
	// The promoting guest hashed the settled image file, so anything short of
	// bit-for-bit equality (corruption in the object store, on the wire, or in
	// this host's RAM) declines here. The inventory digest below cannot catch it:
	// it hashes entry names and sizes, not contents.
	if head.ContentDigest != "" {
		got, err := fileSHA256(image)
		switch {
		case err != nil:
			logger.Error(err, "converge: cannot hash the downloaded image; keeping local master", "want", head.ContentDigest)
			return false, false
		case got != head.ContentDigest:
			logger.Info("converge: image content hash does not match HEAD; keeping local master",
				"want", head.ContentDigest, "got", got)
			return false, true
		}
	}
	if head.Digest != "" {
		got, err := w.Volumes.ImageDigest(image)
		switch {
		case err != nil:
			logger.Error(err, "converge: cannot measure the downloaded image; keeping local master", "want", head.Digest)
			return false, false
		case got != head.Digest:
			logger.Info("converge: image digest does not match HEAD; keeping local master", "want", head.Digest, "got", got)
			return false, true
		}
	}
	return true, false
}

// clearStagingExcept removes everything in dir but keep, which a download of the
// same HEAD resumes from.
func clearStagingExcept(dir, keep string) error {
	entries, err := os.ReadDir(dir)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, entry := range entries {
		if path := filepath.Join(dir, entry.Name()); path != keep {
			_ = os.RemoveAll(path)
		}
	}
	return os.MkdirAll(dir, 0o755)
}

// downloadStats is what a download moved: bytes received and HTTP attempts.
type downloadStats struct {
	bytes    int64
	attempts int
}

// download fetches the HEAD image to dst, resuming from whatever dst already
// holds, and retries a transfer that fails partway. resumed reports whether any
// of dst's bytes came from an earlier transfer.
func (w *ConvergeWorker) download(ctx context.Context, req convergeRequest, dst string) (resumed bool, stats downloadStats, err error) {
	backoff := w.retryBackoff
	if backoff <= 0 {
		backoff = convergeRetryBackoff
	}
	for attempt := 1; ; attempt++ {
		offset := int64(0)
		if info, statErr := os.Stat(dst); statErr == nil {
			offset = info.Size()
		}
		if offset > 0 {
			resumed = true
		}
		var written int64
		written, err = w.fetch(ctx, req, dst, offset)
		stats.bytes += written
		stats.attempts++
		if err == nil {
			return resumed, stats, nil
		}
		var perm permanentDownloadError
		terminal := errors.Is(err, errConvergeYielded) || errors.Is(err, errConvergeDisplaced)
		if errors.As(err, &perm) || terminal || ctx.Err() != nil || attempt >= convergeDownloadAttempts {
			return resumed, stats, err
		}
		log.Log.WithName("volume").Info("converge: master download interrupted; resuming",
			"account", req.key.account, "volume", req.key.volume, "attempt", attempt, "error", err.Error())
		select {
		case <-ctx.Done():
			return resumed, stats, ctx.Err()
		case <-time.After(backoff):
		}
		if !w.mayDownload() {
			return resumed, stats, errConvergeYielded
		}
	}
}

func (w *ConvergeWorker) httpClient() *http.Client {
	if w.client != nil {
		return w.client
	}
	return masterDownloadClient
}

// masterDownloadClient refuses redirects: a presigned object-storage URL is
// served directly, so following one could only bounce this host to an address
// the server never vetted. The server checks the URL's host is public before
// handing it out (see volume_head_payload).
var masterDownloadClient = &http.Client{
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	Transport: &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		ResponseHeaderTimeout: time.Minute,
		TLSHandshakeTimeout:   30 * time.Second,
	},
}

// fetch runs one transfer of the HEAD image into dst from byte offset and
// returns how many bytes it received.
func (w *ConvergeWorker) fetch(ctx context.Context, req convergeRequest, dst string, offset int64) (int64, error) {
	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, req.head.DownloadURL, nil)
	if err != nil {
		return 0, permanent(err)
	}
	if httpReq.URL.Scheme != "https" && httpReq.URL.Scheme != "http" {
		return 0, permanent(fmt.Errorf("unsupported download URL scheme %q", httpReq.URL.Scheme))
	}
	if offset > 0 {
		httpReq.Header.Set("Range", "bytes="+strconv.FormatInt(offset, 10)+"-")
	}
	resp, err := w.httpClient().Do(httpReq)
	if err != nil {
		if cause := context.Cause(ctx); cause != nil && !errors.Is(cause, context.Canceled) {
			return 0, cause
		}
		return 0, err
	}
	defer resp.Body.Close()

	var total int64
	switch {
	case resp.StatusCode == http.StatusPartialContent && offset > 0:
		start, size, ok := parseContentRange(resp.Header.Get("Content-Range"))
		if !ok || start != offset {
			_ = os.Remove(dst)
			return 0, fmt.Errorf("unexpected Content-Range %q for a resume from %d", resp.Header.Get("Content-Range"), offset)
		}
		total = size
	case resp.StatusCode == http.StatusOK:
		// The server ignored the range; start over.
		offset = 0
		total = resp.ContentLength
		if total < 0 {
			return 0, permanent(errors.New("master download has no Content-Length"))
		}
	case resp.StatusCode == http.StatusRequestedRangeNotSatisfiable && offset > 0:
		if _, size, ok := parseContentRange(resp.Header.Get("Content-Range")); ok && size == offset {
			return 0, nil
		}
		_ = os.Remove(dst)
		return 0, fmt.Errorf("partial download is not a prefix of the master (Content-Range %q)", resp.Header.Get("Content-Range"))
	case resp.StatusCode >= 400 && resp.StatusCode < 500:
		// An expired or revoked presigned URL, or an object that is gone.
		return 0, permanent(fmt.Errorf("master download: HTTP %d", resp.StatusCode))
	default:
		return 0, fmt.Errorf("master download: HTTP %d", resp.StatusCode)
	}

	reservation, err := w.Volumes.PrepareConvergeSpace(req.key, uint64(total), uint64(total-offset), req.source == convergeSourceJob, cancel)
	if err != nil {
		return 0, permanent(err)
	}
	defer reservation.Release()

	f, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE, 0o644)
	if err != nil {
		return 0, permanent(err)
	}
	defer f.Close()
	noPageCache(f)
	if err := f.Truncate(offset); err != nil {
		return 0, permanent(err)
	}
	if _, err := f.Seek(offset, io.SeekStart); err != nil {
		return 0, permanent(err)
	}

	var progress atomic.Int64
	progress.Store(w.clock().UnixNano())
	var busy atomic.Bool
	busy.Store(w.Volumes.jobsRunning() > 0)
	stall := w.stallTimeout
	if stall <= 0 {
		stall = convergeStallTimeout
	}
	check := w.poll()
	if check > stall/2 {
		check = stall / 2
	}
	done := make(chan struct{})
	defer close(done)
	go func() {
		t := time.NewTicker(check)
		defer t.Stop()
		for {
			select {
			case <-done:
				return
			case <-ctx.Done():
				return
			case <-t.C:
			}
			busy.Store(w.Volumes.jobsRunning() > 0)
			if !w.mayDownload() {
				cancel(errConvergeYielded)
				return
			}
			if w.clock().Sub(time.Unix(0, progress.Load())) > stall {
				cancel(errConvergeStalled)
				return
			}
		}
	}()

	rate := w.busyBytesPerSec
	if rate <= 0 {
		rate = convergeBusyBytesPerSecond
	}
	throttle := downloadThrottle{rate: rate}
	written, err := copyWithProgress(ctx, f, resp.Body, func(n int) {
		reservation.Wrote(n)
		progress.Store(w.clock().UnixNano())
		throttle.wait(ctx, n, busy.Load())
	})
	if cause := context.Cause(ctx); cause != nil && !errors.Is(cause, context.Canceled) {
		return written, cause
	}
	if err != nil {
		return written, err
	}
	if err := f.Close(); err != nil {
		return written, err
	}
	if written != total-offset {
		return written, fmt.Errorf("master download ended after %d of %d bytes", offset+written, total)
	}
	return written, nil
}

func copyWithProgress(ctx context.Context, dst io.Writer, src io.Reader, onChunk func(int)) (int64, error) {
	buf := make([]byte, 1<<20)
	var written int64
	for {
		if err := ctx.Err(); err != nil {
			return written, err
		}
		n, rerr := src.Read(buf)
		if n > 0 {
			if _, werr := dst.Write(buf[:n]); werr != nil {
				return written, werr
			}
			written += int64(n)
			onChunk(n)
		}
		if rerr == io.EOF {
			return written, nil
		}
		if rerr != nil {
			return written, rerr
		}
	}
}

// downloadThrottle holds a transfer to rate bytes per second while a job runs
// on the host, and lets it run free otherwise.
type downloadThrottle struct {
	rate  float64
	start time.Time
	bytes int64
}

func (t *downloadThrottle) wait(ctx context.Context, n int, busy bool) {
	if !busy {
		t.start = time.Time{}
		return
	}
	now := time.Now()
	if t.start.IsZero() {
		t.start, t.bytes = now, 0
	}
	t.bytes += int64(n)
	ahead := time.Duration(float64(t.bytes)/t.rate*float64(time.Second)) - now.Sub(t.start)
	if ahead <= 0 {
		return
	}
	select {
	case <-ctx.Done():
	case <-time.After(ahead):
	}
}

// parseContentRange parses "bytes <start>-<end>/<size>" or "bytes */<size>".
func parseContentRange(header string) (start, size int64, ok bool) {
	rest, found := strings.CutPrefix(header, "bytes ")
	if !found {
		return 0, 0, false
	}
	span, sizeText, found := strings.Cut(rest, "/")
	if !found {
		return 0, 0, false
	}
	size, err := strconv.ParseInt(sizeText, 10, 64)
	if err != nil || size < 0 {
		return 0, 0, false
	}
	if span == "*" {
		return 0, size, true
	}
	startText, _, found := strings.Cut(span, "-")
	if !found {
		return 0, 0, false
	}
	start, err = strconv.ParseInt(startText, 10, 64)
	if err != nil || start < 0 {
		return 0, 0, false
	}
	return start, size, true
}
