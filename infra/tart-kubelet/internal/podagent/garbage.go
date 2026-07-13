// Garbage collection for Tart-managed disk. Lives in podagent so it
// shares the Pod ↔ VM name mapping with the reconciler.
//
// Without this, the host fills with leftover clones from terminated
// Pods + tag-superseded OCI images and `tart pull` eventually fails
// with "The file couldn't be saved because there isn't enough
// space.", which the reconciler can't recover from on its own.
//
// Two entry points:
//   - `Start` is a controller-runtime Runnable that fires every
//     `Interval` to drop orphan local VMs and stale OCI cache entries.
//   - `RunOnce` is invoked synchronously by the reconciler when a
//     Pull errors with a no-space signature, before retrying.
//
// "Backed by a Pod" = the VM's name matches `VMNameForPod` of some
// Pod scheduled to this Node OR the OCI cache entry matches some
// Pod's container image.
package podagent

import (
	"context"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// Collector is a controller-runtime Runnable that periodically
// reclaims Tart-managed disk on the local Mac mini.
//
// Store, when set, contributes to the "expected" set on every pass.
// Without it there's a window where a Pod has just been admitted, the
// reconciler has already kicked off `tart pull` / `tart clone`, but
// the Pod isn't yet visible on the API server's List response — and
// the GC would happily delete the VM the reconciler just created.
// Folding Store into expectedSet closes that window: any VM the
// reconciler has explicitly registered counts as live regardless of
// what API List returned.
type Collector struct {
	K8s      client.Reader
	Tart     *tart.Client
	NodeName string
	Interval time.Duration
	Store    *Store

	// GoldenRetention is how long a golden base VM with no current Pod
	// referencing its digest is kept before reaping. It lets a golden
	// survive idle troughs — an overnight-quiet host clones the morning
	// burst from its golden instead of re-pulling the whole image — and
	// a digest's golden linger briefly after a roll. Zero falls back to
	// defaultGoldenRetention. Disk-pressure reclaim (RunOnceReclaim)
	// ignores it.
	GoldenRetention time.Duration

	// Now is overridable in tests; defaults to time.Now.
	Now func() time.Time

	// IsRunning probes whether a VM has a live `tart run` process, gating
	// every reap so an in-use VM is never deleted mid-session. Overridable
	// in tests (pgrep isn't stubbable via the Tart binary); defaults to
	// Tart.IsRunning.
	IsRunning func(ctx context.Context, name string) (bool, error)

	mu sync.Mutex

	// goldenSeen tracks the last time each golden base VM was seen
	// referenced (or first seen unreferenced), powering GoldenRetention.
	// In-memory: on kubelet restart it reseeds on first sight, erring
	// toward keeping a golden one extra window — safe (a re-pull avoided,
	// disk reclaimed slightly later).
	goldenSeenMu sync.Mutex
	goldenSeen   map[string]time.Time
}

// defaultGoldenRetention keeps an unreferenced golden base for a day —
// long enough to span an overnight idle trough so the next burst clones
// from it rather than re-pulling, short enough that a rolled-out digest's
// golden is reclaimed within a day.
const defaultGoldenRetention = 24 * time.Hour

// Start blocks until ctx is cancelled. Conforms to manager.Runnable.
func (c *Collector) Start(ctx context.Context) error {
	c.RunOnce(ctx)
	t := time.NewTicker(c.Interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			c.RunOnce(ctx)
		}
	}
}

// RunOnce performs a single GC pass, keeping unreferenced golden base
// VMs within GoldenRetention. Safe to call concurrently with itself
// (mutex serializes). Logs but doesn't return errors — there's nothing
// the caller can usefully do with them.
func (c *Collector) RunOnce(ctx context.Context) { c.runOnce(ctx, false) }

// RunOnceReclaim is the aggressive variant the reconciler calls when a
// pull fails for lack of space: it additionally evicts unreferenced
// golden bases regardless of GoldenRetention, since a golden held only
// as a warm-clone source must yield to an actual out-of-disk provision.
func (c *Collector) RunOnceReclaim(ctx context.Context) { c.runOnce(ctx, true) }

func (c *Collector) runOnce(ctx context.Context, aggressive bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	logger := log.FromContext(ctx).WithName("gc")

	expected, err := c.expectedSet(ctx)
	if err != nil {
		logger.Error(err, "list pods scheduled to this node")
		return
	}

	vms, err := c.Tart.List(ctx)
	if err != nil {
		logger.Error(err, "list tart entries")
		return
	}

	now := c.now()
	retention := c.GoldenRetention
	if retention <= 0 {
		retention = defaultGoldenRetention
	}

	var droppedClones, droppedImages, droppedGoldens int
	for _, vm := range vms {
		switch vm.Source {
		case "local":
			// Golden bases survive the no-Pod recycle gap (and idle
			// troughs) so recycles clone from them instead of re-pulling.
			// A non-golden local VM with no backing Pod is an orphan
			// clone, reaped immediately as before.
			if isGoldenVMName(vm.Name) {
				if c.keepGolden(vm.Name, expected, now, retention, aggressive) {
					continue
				}
				if c.live(ctx, vm.Name) {
					logger.Info("spared golden base: a tart run process is live", "name", vm.Name)
					continue
				}
				if err := c.Tart.Delete(ctx, vm.Name); err != nil {
					logger.Error(err, "delete stale golden base", "name", vm.Name)
					continue
				}
				c.forgetGolden(vm.Name)
				droppedGoldens++
				continue
			}
			if _, want := expected.vms[vm.Name]; want {
				continue
			}
			if c.live(ctx, vm.Name) {
				logger.Info("spared orphan VM: a tart run process is live", "name", vm.Name)
				continue
			}
			if err := c.Tart.Delete(ctx, vm.Name); err != nil {
				logger.Error(err, "delete orphan VM", "name", vm.Name)
				continue
			}
			_ = c.Tart.CleanupVMUserData(vm.Name)
			droppedClones++
		case "OCI":
			// Keep a cached image whose repository a Pod still references.
			// Pods name images by tag and Tart lists them by digest, so the
			// match is on the repository the two share — without it the GC
			// reaped the live runner image every pass. Under aggressive
			// (disk-pressure) reclaim, reap it anyway: the OCI cache is
			// reconstructible by re-pull, so an actual out-of-disk provision
			// must win over keeping it warm (mirrors the golden policy, and
			// bounds the superseded-digest tail a referenced repo accrues).
			if _, want := expected.imageRepos[ociRepository(vm.Name)]; want && !aggressive {
				continue
			}
			if err := c.Tart.Delete(ctx, vm.Name); err != nil {
				logger.Error(err, "delete stale OCI cache entry", "image", vm.Name)
				continue
			}
			droppedImages++
		}
	}
	if droppedClones > 0 || droppedImages > 0 || droppedGoldens > 0 {
		logger.Info("reclaimed disk",
			"orphan_clones", droppedClones,
			"stale_oci_images", droppedImages,
			"stale_golden_bases", droppedGoldens)
	}
}

// keepGolden decides whether to retain a golden base VM this pass and
// stamps its last-seen time. A golden whose digest a current Pod still
// references is always kept (and its retention clock reset). An
// unreferenced golden is kept until GoldenRetention elapses since it was
// last seen — except under `aggressive` reclaim, where unreferenced
// always means reap. First unreferenced sighting starts the clock now
// (covers a just-materialized golden the Pod List hasn't caught up to,
// and pre-restart goldens), so it's never reaped on the very pass that
// discovers it.
func (c *Collector) keepGolden(name string, expected *expectedSet, now time.Time, retention time.Duration, aggressive bool) bool {
	c.goldenSeenMu.Lock()
	defer c.goldenSeenMu.Unlock()
	if c.goldenSeen == nil {
		c.goldenSeen = map[string]time.Time{}
	}

	if _, referenced := expected.vms[name]; referenced {
		c.goldenSeen[name] = now
		return true
	}
	if aggressive {
		return false
	}
	last, ok := c.goldenSeen[name]
	if !ok {
		c.goldenSeen[name] = now
		return true
	}
	return now.Sub(last) < retention
}

// forgetGolden drops a reaped golden's last-seen entry so the map
// doesn't grow without bound across digest rolls.
func (c *Collector) forgetGolden(name string) {
	c.goldenSeenMu.Lock()
	delete(c.goldenSeen, name)
	c.goldenSeenMu.Unlock()
}

func (c *Collector) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

// live reports whether a VM must be spared this pass because a `tart run`
// process is currently executing for it. A probe error counts as live
// (fail-safe): deleting a VM that might be running is the harmful outcome,
// so an unreadable liveness signal skips the reap and lets the next pass
// retry — matching the reconciler, which treats an IsRunning error as
// "assume alive." Golden bases are meant to be inert copy-on-write sources
// that are never run in production, but the GC must not bank on that: a
// benchmark or operator that boots one directly must not have it deleted
// out from under a live session.
func (c *Collector) live(ctx context.Context, name string) bool {
	probe := c.IsRunning
	if probe == nil {
		probe = c.Tart.IsRunning
	}
	running, err := probe(ctx, name)
	if err != nil {
		return true
	}
	return running
}

// IsNoSpaceError matches the stderr signature Tart returns when a
// pull/clone/run can't write because the disk is full. Stable enough
// across Tart 2.x to gate the disk-pressure GC on.
func IsNoSpaceError(err error) bool {
	if err == nil {
		return false
	}
	s := err.Error()
	return strings.Contains(s, "isn’t enough space") || // curly apostrophe used by Foundation
		strings.Contains(s, "isn't enough space") ||
		strings.Contains(s, "database or disk is full") ||
		strings.Contains(s, "No space left on device")
}

type expectedSet struct {
	vms map[string]struct{}
	// imageRepos holds the repository (registry/name with the tag and
	// digest stripped) of every referenced Pod image. The OCI branch
	// matches against this rather than the full ref: a Pod requests its
	// image by tag (`…/tuist-runner:macos-26-5-0.7.0`), but Tart caches
	// it under — and `tart list` reports it by — the resolved digest
	// (`…/tuist-runner@sha256:…`). The old full-ref comparison never
	// matched, so the GC marked the live runner image stale and deleted
	// it on every pass, forcing the next golden materialization into a
	// full multi-GB re-pull instead of a clonefile from the warm cache.
	imageRepos map[string]struct{}
}

func (c *Collector) expectedSet(ctx context.Context) (*expectedSet, error) {
	pods := &corev1.PodList{}
	if err := c.K8s.List(ctx, pods, client.MatchingFields{"spec.nodeName": c.NodeName}); err != nil {
		return nil, err
	}
	out := &expectedSet{
		vms:        map[string]struct{}{},
		imageRepos: map[string]struct{}{},
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		// Pods being deleted are about to release their VMs; let the
		// reconciler's DeletePod handle them. GC stays out of the way.
		if pod.DeletionTimestamp != nil {
			continue
		}
		if len(pod.Spec.Containers) != 1 {
			continue
		}
		out.vms[VMNameForPod(pod)] = struct{}{}
		out.imageRepos[ociRepository(pod.Spec.Containers[0].Image)] = struct{}{}
		// Keep the golden base this image clones from. Without this the
		// "local" GC branch would see the golden VM, find no Pod named
		// after it, and reap it as an orphan clone — forcing the next
		// recycle to re-pull the whole image.
		out.vms[goldenVMName(pod.Spec.Containers[0].Image)] = struct{}{}
	}
	// Store-side entries cover Pods the reconciler has already started
	// a VM for but that haven't shown up on this List response yet
	// (e.g. just-admitted Pods, or pods re-bound to this Node by
	// startup recovery). The image-repo set is intentionally not
	// augmented from Store: Store doesn't track the originating image,
	// and the OCI cache GC is allowed to be one cycle behind reality.
	if c.Store != nil {
		for _, e := range c.Store.Snapshot() {
			out.vms[e.VMName] = struct{}{}
		}
	}
	return out, nil
}

// ociRepository strips the tag and/or digest from an OCI image
// reference, returning the bare `registry[:port]/name`. Pods reference
// images by tag while Tart caches and lists them by digest, so the GC
// has to compare on the repository the two share. A registry port (a
// ':' whose suffix still contains a '/') must survive the tag strip.
func ociRepository(ref string) string {
	if i := strings.IndexByte(ref, '@'); i >= 0 {
		ref = ref[:i]
	}
	if i := strings.LastIndexByte(ref, ':'); i >= 0 && !strings.Contains(ref[i+1:], "/") {
		ref = ref[:i]
	}
	return ref
}
