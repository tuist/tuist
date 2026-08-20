package podagent

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"net/http"
	"net/http/httptest"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func convergeReconciler(m *VolumeManager) *Reconciler {
	return &Reconciler{
		Volumes:                  m,
		ConvergeHeadWaitInterval: time.Millisecond,
		ConvergeHeadWaitAttempts: 2,
		ConvergeDownloadAttempts: 2,
		ConvergeDownloadBackoff:  time.Millisecond,
	}
}

func partialPath(t *testing.T, m *VolumeManager, account, digest string) string {
	t.Helper()
	return filepath.Join(m.Root, convergePartialsDirName, account, ReservedTuistCacheVolume, digest)
}

// The failure this exists for: a master too big to fetch inside one
// convergeDownloadTimeout. Wiping the download every convergence puts such a
// host on a treadmill — it re-pulls the same opening gigabytes on every job and
// never converges at all. Banking the bytes under the HEAD's content address
// turns those jobs into progress.
func TestConvergeMasterBanksProgressAcrossConvergences(t *testing.T) {
	body := masterObject()
	srv := &truncatingServer{body: body, truncate: 2}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	m, _ := newTestManager(t, 100)
	statusDir := t.TempDir()
	head := volumeHead{Generation: 6, Digest: objectDigest(body), DownloadURL: ts.URL}
	stageHead(t, statusDir, head)
	r := convergeReconciler(m)

	// First convergence: every attempt is cut short, so it fails — but banks what
	// it received rather than discarding it.
	r.convergeMaster("vm1", statusDir, ReservedTuistCacheVolume, "42")
	if masterExists(m, "42") {
		t.Fatal("converged despite every attempt being truncated")
	}
	info, err := os.Stat(partialPath(t, m, "42", head.Digest))
	if err != nil {
		t.Fatalf("no partial banked for the next convergence: %v", err)
	}
	banked := info.Size()
	if banked == 0 || banked >= int64(len(body)) {
		t.Fatalf("banked %d bytes of a %d-byte object; expected a partial", banked, len(body))
	}

	resumedBefore := testutil.ToFloat64(cacheVolumeConvergeResumedTotal)

	// Second convergence, a later job: picks up where the first stopped.
	r.convergeMaster("vm2", statusDir, ReservedTuistCacheVolume, "42")

	if !masterExists(m, "42") {
		t.Fatal("the second convergence did not finish the banked download")
	}
	if gen, err := m.MasterGeneration("42", ReservedTuistCacheVolume); err != nil || gen != 6 {
		t.Fatalf("master generation = %d (%v), want 6", gen, err)
	}
	if got := testutil.ToFloat64(cacheVolumeConvergeResumedTotal); got != resumedBefore+1 {
		t.Fatalf("converge_resumed_total = %v, want %v", got, resumedBefore+1)
	}
	// Every byte crossed the wire once. Restarting from zero would have re-sent
	// the banked prefix, which is the amplification this avoids.
	if _, served := srv.requests(); served >= 2*len(body) {
		t.Fatalf("served %d bytes for a %d-byte object; progress was not resumed", served, len(body))
	}
	// Adopted, so the bytes have done their job and must not linger on a
	// quota-bound volume.
	if _, err := os.Stat(partialPath(t, m, "42", head.Digest)); !os.IsNotExist(err) {
		t.Fatalf("partial survived a successful convergence: %v", err)
	}
}

// A partial is only ever adoptable for the digest it was banked under, so when
// the HEAD moves on the old one is dead weight on a volume that evicts masters
// to make room.
func TestConvergeMasterDropsPartialsForASupersededHead(t *testing.T) {
	body := masterObject()
	srv := &truncatingServer{body: body, truncate: 99}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	m, _ := newTestManager(t, 100)
	statusDir := t.TempDir()
	stale := objectDigest([]byte("the generation before this one"))
	r := convergeReconciler(m)

	stageHead(t, statusDir, volumeHead{Generation: 6, Digest: stale, DownloadURL: ts.URL})
	r.convergeMaster("vm1", statusDir, ReservedTuistCacheVolume, "42")
	if _, err := os.Stat(partialPath(t, m, "42", stale)); err != nil {
		t.Fatalf("no partial banked to supersede: %v", err)
	}

	// The account promotes again; this host now converges toward a new digest.
	fresh := objectDigest(body)
	stageHead(t, statusDir, volumeHead{Generation: 7, Digest: fresh, DownloadURL: ts.URL})
	r.convergeMaster("vm2", statusDir, ReservedTuistCacheVolume, "42")

	if _, err := os.Stat(partialPath(t, m, "42", stale)); !os.IsNotExist(err) {
		t.Fatalf("superseded partial still on the volume: %v", err)
	}
	if _, err := os.Stat(partialPath(t, m, "42", fresh)); err != nil {
		t.Fatalf("current HEAD's partial was not banked: %v", err)
	}
}

// A completed download that measures wrong is disproved, not incomplete.
// Keeping it would re-measure the same disproved bytes on every convergence
// from then on, which is worse than the treadmill it replaced.
func TestConvergeMasterDropsAPartialThatMeasuredWrong(t *testing.T) {
	body := masterObject()
	srv := &truncatingServer{body: body}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	m, _ := newTestManager(t, 100)
	statusDir := t.TempDir()
	advertised := objectDigest([]byte("not what the object holds"))
	stageHead(t, statusDir, volumeHead{Generation: 6, Digest: advertised, DownloadURL: ts.URL})

	convergeReconciler(m).convergeMaster("vm1", statusDir, ReservedTuistCacheVolume, "42")

	if masterExists(m, "42") {
		t.Fatal("adopted an image whose digest did not match the HEAD")
	}
	if _, err := os.Stat(partialPath(t, m, "42", advertised)); !os.IsNotExist(err) {
		t.Fatalf("disproved download kept as a partial: %v", err)
	}
}

// Space pressure resolves against the speculative thing first: a partial is a
// download that has not paid off, a master is warmth a job can already use.
func TestEvictionGivesUpPartialsBeforeMasters(t *testing.T) {
	root := t.TempDir()
	// perMaster 0 so the master itself costs nothing in the fake's accounting and
	// the only thing between free space and the watermark is the partial.
	be := &fakeBackend{totalBytes: 3 * gib / 2, perMaster: 0, root: root}
	m := NewVolumeManager(root, 1, be)
	seedMasterGen(t, m, "42", masterImageContent("42"), 3)

	partial, _, err := m.ConvergePartial("42", ReservedTuistCacheVolume, "somedigest")
	if err != nil {
		t.Fatalf("ConvergePartial: %v", err)
	}
	// Sparse: the size is what the volume accounts for, the blocks are not needed.
	f, err := os.Create(partial)
	if err != nil {
		t.Fatalf("create the partial: %v", err)
	}
	if err := f.Truncate(int64(gib / 2)); err != nil {
		t.Fatalf("size the partial: %v", err)
	}
	f.Close()
	if free, err := be.freeBytes(root); err != nil || free >= m.lowWatermarkBytes() {
		t.Fatalf("test does not put the volume under pressure: free=%d target=%d (%v)", free, m.lowWatermarkBytes(), err)
	}

	evicted, err := m.EvictToWatermark()
	if err != nil {
		t.Fatalf("EvictToWatermark: %v", err)
	}

	if _, err := os.Stat(partial); !os.IsNotExist(err) {
		t.Fatalf("partial survived eviction: %v", err)
	}
	if !masterExists(m, "42") {
		t.Fatal("evicted a resident master while a speculative partial was still on the volume")
	}
	if evicted != 0 {
		t.Fatalf("evicted %d masters; giving up the partial was enough", evicted)
	}
}

// Two VMs on one host can be dispatched to the same account. Without
// serialization they would fetch into the same content-addressed partial at
// once; with it, the second finds the first's install already done.
func TestConvergeMasterSerializesPerAccount(t *testing.T) {
	body := masterObject()
	srv := &truncatingServer{body: body}
	ts := httptest.NewServer(http.HandlerFunc(srv.handle))
	defer ts.Close()

	m, _ := newTestManager(t, 100)
	statusDir := t.TempDir()
	stageHead(t, statusDir, volumeHead{Generation: 6, Digest: objectDigest(body), DownloadURL: ts.URL})
	r := convergeReconciler(m)

	var wg sync.WaitGroup
	for _, vm := range []string{"vm1", "vm2"} {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r.convergeMaster(vm, statusDir, ReservedTuistCacheVolume, "42")
		}()
	}
	wg.Wait()

	if !masterExists(m, "42") {
		t.Fatal("neither convergence installed the master")
	}
	// The loser re-reads the generation gate under the lock and declines, so the
	// object is fetched once, not twice.
	if starts, _ := srv.requests(); len(starts) != 1 {
		t.Fatalf("requests = %v, want one (the second convergence should find the master already at the HEAD)", starts)
	}
}
