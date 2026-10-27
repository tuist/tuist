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

	"github.com/tuist/tuist/infra/tart-kubelet/internal/hostdisk"
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

	// Images, when set, names the rack image caches pulls may come from, so
	// an OCI entry pulled through one counts as its upstream repository.
	Images *ImageSources

	// Fleet is this Node's `tuist.dev/fleet` label. When the fleet has macOS
	// RunnerPools, a golden or OCI cache entry for an image none of them runs
	// any more and no Pod here references is reaped on the next pass instead
	// of after GoldenRetention: runner images are released several times a
	// day, and a host that kept every superseded image for a day held 19 of
	// them (~1.1 TiB) beside the 2 it could still use. A fleet without pools,
	// or a failed RunnerPool List, keeps the retention behaviour.
	Fleet string

	// HostDiskFreeFloor is the root-volume free-space percentage below
	// which the collector reclaims golden bases even when a Pod still
	// references their digest. This is the only bound on goldens of images
	// a pool still runs: keepGolden always keeps a referenced golden, and the
	// runners-controller pins a warm Pod per Xcode-version pool to a host
	// (golden node-affinity), so every golden stays permanently referenced
	// and the retention pass never reaps it — the disk fills to 100% (~6
	// goldens on a 460GiB mini) and every operator SSH update then fails
	// with "No space left on device" while the Node still looks Ready. Set
	// above the DiskPressure floor so reclaim runs before the node reports
	// pressure. Zero falls back to defaultGoldenReclaimFreeFloor.
	HostDiskFreeFloor float64

	// HostDiskFree probes the host root volume's free-space percent.
	// Overridable in tests (statvfs isn't stubbable via the Tart binary);
	// defaults to a real statvfs of "/".
	HostDiskFree func() (float64, error)

	// MinGoldensKept floors how many golden bases the disk-pressure
	// reclaim leaves behind, so a wedged measurement or a pathological
	// host never strands it with zero warm bases (every subsequent launch
	// cold-pulls). Zero falls back to defaultMinGoldensKept.
	MinGoldensKept int

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

	// Goldens pulls a pool's current image when this host holds its previous
	// one (see follow.go). Nil disables following releases.
	Goldens goldenEnsurer

	// FollowTimeout overrides defaultFollowTimeout.
	FollowTimeout time.Duration

	followMu      sync.Mutex
	followSince   map[string]time.Time
	followRunning bool
	followWG      sync.WaitGroup
}

// defaultGoldenRetention keeps an unreferenced golden base for a day —
// long enough to span an overnight idle trough so the next burst clones
// from it rather than re-pulling, short enough that a rolled-out digest's
// golden is reclaimed within a day.
const defaultGoldenRetention = 24 * time.Hour

// defaultGoldenReclaimFreeFloor keeps the host above 15% free by reclaiming
// golden bases, leaving headroom above the 10% DiskPressure/alert floor so
// the disk-pressure reclaim fires and frees space before the Node ever
// reports pressure.
const defaultGoldenReclaimFreeFloor = 15.0

// defaultMinGoldensKept never lets the disk-pressure reclaim strand a host
// with zero warm bases.
const defaultMinGoldensKept = 1

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

	// Host-disk pressure escalates this whole pass to aggressive. Goldens are
	// APFS copy-on-write clones of their pulled OCI image (tart clone), so
	// reaping a golden while the normal pass KEEPS its referenced OCI source
	// frees only metadata — the ~68 GiB of backing blocks stay alive as long
	// as the OCI entry references them. Aggressive mode also evicts the OCI
	// cache (reconstructible by re-pull), so the golden and its source both
	// go and the blocks are actually released. A stacked golden holds only a
	// manifest and an overlay; its base lives in Tart's content store, which
	// collectContent releases once neither a golden nor a cached image
	// references it. The referenced-golden reclaim below then handles the
	// bases keepGolden pins. A probe error just skips the escalation this pass
	// (the periodic retention behaviour still runs).
	floor := c.goldenReclaimFreeFloor()
	free, freeErr := c.hostDiskFree()
	underPressure := freeErr == nil && free < floor
	if underPressure {
		aggressive = true
	}

	var follow []string
	if !aggressive {
		follow = c.planFollow(expected, vms, now)
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
			// Under aggressive (disk-pressure) reclaim, reap it anyway: the
			// OCI cache is reconstructible by re-pull, so an actual
			// out-of-disk provision must win over keeping it warm (mirrors
			// the golden policy).
			if expected.keepsImage(vm.Name) && !aggressive {
				continue
			}
			if err := c.Tart.Delete(ctx, vm.Name); err != nil {
				logger.Error(err, "delete stale OCI cache entry", "image", vm.Name)
				continue
			}
			droppedImages++
		}
	}
	if droppedGoldens > 0 {
		c.collectContent(ctx)
	}
	if droppedClones > 0 || droppedImages > 0 || droppedGoldens > 0 {
		logger.Info("reclaimed disk",
			"orphan_clones", droppedClones,
			"stale_oci_images", droppedImages,
			"stale_golden_bases", droppedGoldens)
	}

	// The retention pass above never reaps a referenced golden; enforce the
	// host-disk bound that actually keeps the mini from filling. Only under
	// pressure — the aggressive main loop already freed what it could.
	if underPressure {
		c.reclaimGoldensUnderDiskPressure(ctx, expected, floor)
	}

	c.startFollow(ctx, follow)
}

// reclaimGoldensUnderDiskPressure is the bound the retention pass lacks:
// while the host root volume is below the free-space floor, it reaps golden
// bases even if a Pod still references their digest (keepGolden always keeps
// those, so a warm Pod per Xcode pool otherwise pins every golden and the
// disk fills unbounded). It reaps least-valuable first — unreferenced
// goldens (superseded digests), then referenced ones whose clone isn't
// currently running (idle warm-pool bases) — never touches a golden that
// backs a live clone, spares any golden with a live `tart run`, keeps at
// least MinGoldensKept, and stops the moment free space recovers. A reaped
// golden re-pulls on its pool's next launch; that one cold clone is the
// deliberate price of not letting the disk fill and silently break the
// operator's SSH-driven config updates.
//
// The caller runs the aggressive main loop first (which evicts the OCI
// sources these goldens clone from, so a golden delete actually releases
// blocks rather than metadata), then this re-measures: if evicting the OCI
// cache + unreferenced goldens already cleared the pressure, the warm
// referenced goldens are left alone.
func (c *Collector) reclaimGoldensUnderDiskPressure(ctx context.Context, expected *expectedSet, floor float64) {
	logger := log.FromContext(ctx).WithName("gc")

	free, err := c.hostDiskFree()
	if err != nil {
		logger.Error(err, "measure host disk free; skipping golden disk-pressure reclaim")
		return
	}
	if free >= floor {
		return
	}

	minKept := c.MinGoldensKept
	if minKept <= 0 {
		minKept = defaultMinGoldensKept
	}

	// Re-list rather than reuse the caller's inventory: the aggressive main
	// loop just deleted unreferenced goldens + OCI entries, so a stale list
	// would count already-deleted goldens toward `total` (their re-delete
	// fails without advancing `reaped`) and could delete the last real base.
	vms, err := c.Tart.List(ctx)
	if err != nil {
		logger.Error(err, "re-list tart entries for golden disk-pressure reclaim")
		return
	}

	// Reap order: unreferenced (stalest) first, then referenced-but-idle.
	// Goldens backing a live clone are excluded entirely.
	liveBacked := c.liveBackedGoldens(ctx)
	var unreferenced, idleReferenced []string
	total := 0
	for _, vm := range vms {
		if vm.Source != "local" || !isGoldenVMName(vm.Name) {
			continue
		}
		total++
		if _, backed := liveBacked[vm.Name]; backed {
			continue
		}
		if _, ref := expected.vms[vm.Name]; ref {
			idleReferenced = append(idleReferenced, vm.Name)
		} else {
			unreferenced = append(unreferenced, vm.Name)
		}
	}

	reaped := 0
	for _, name := range append(unreferenced, idleReferenced...) {
		if free >= floor || total-reaped <= minKept {
			break
		}
		if c.live(ctx, name) {
			continue
		}
		if err := c.Tart.Delete(ctx, name); err != nil {
			logger.Error(err, "delete golden under host disk pressure", "name", name)
			continue
		}
		c.forgetGolden(name)
		reaped++
		c.collectContent(ctx)
		if f, ferr := c.hostDiskFree(); ferr == nil {
			free = f
		}
	}

	switch {
	case reaped > 0:
		logger.Info("reclaimed golden bases under host disk pressure",
			"reaped", reaped, "host_free_percent", free, "floor", floor)
	case free < floor:
		logger.Info("host disk below free floor but no reclaimable golden bases (all live-backed or at minimum kept)",
			"host_free_percent", free, "floor", floor, "min_kept", minKept)
	}
}

// goldenReclaimFreeFloor is the root-volume free-space percent below which
// the disk-pressure golden reclaim runs, defaulting when unset.
func (c *Collector) goldenReclaimFreeFloor() float64 {
	if c.HostDiskFreeFloor > 0 {
		return c.HostDiskFreeFloor
	}
	return defaultGoldenReclaimFreeFloor
}

// hostDiskFree returns the host root volume's free-space percent, using the
// injected probe when set (tests) or a real statvfs of "/".
func (c *Collector) hostDiskFree() (float64, error) {
	if c.HostDiskFree != nil {
		return c.HostDiskFree()
	}
	st, err := hostdisk.Root("/")
	if err != nil {
		return 0, err
	}
	return st.FreePercent(), nil
}

// liveBackedGoldens returns the set of golden base VM names whose clone is
// currently running a Pod on this Node — the bases a disk-pressure reclaim
// must not reap, since deleting them would force the active pool to
// cold-pull its next launch. A List error yields the empty set: with no
// evidence a golden is in use, the reclaim's other guards (live probe,
// MinGoldensKept) still hold.
func (c *Collector) liveBackedGoldens(ctx context.Context) map[string]struct{} {
	out := map[string]struct{}{}
	pods := &corev1.PodList{}
	if err := c.K8s.List(ctx, pods, client.MatchingFields{"spec.nodeName": c.NodeName}); err != nil {
		return out
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.DeletionTimestamp != nil || len(pod.Spec.Containers) != 1 {
			continue
		}
		if c.live(ctx, VMNameForPod(pod)) {
			out[goldenVMName(pod.Spec.Containers[0].Image)] = struct{}{}
		}
	}
	return out
}

// keepGolden decides whether to retain a golden base VM this pass and
// stamps its last-seen time. A golden whose digest a current Pod still
// references is always kept (and its retention clock reset). An
// unreferenced golden of an image no pool of the fleet runs is reaped. Any
// other unreferenced golden is kept until GoldenRetention elapses since it
// was last seen — except under `aggressive` reclaim, where unreferenced
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
	if _, following := expected.following[name]; following && !aggressive {
		return true
	}
	if aggressive || expected.superseded(name) {
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
	// digest stripped) of every referenced Pod image. Without pools, the
	// OCI branch matches against this rather than the full ref: a Pod may
	// request its image by tag (`…/tuist-runner:macos-26-5-0.7.0`), but Tart caches
	// it under — and `tart list` reports it by — the resolved digest
	// (`…/tuist-runner@sha256:…`). The old full-ref comparison never
	// matched, so the GC marked the live runner image stale and deleted
	// it on every pass, forcing the next golden materialization into a
	// full multi-GB re-pull instead of a clonefile from the warm cache.
	imageRepos map[string]struct{}

	// poolGoldens holds the golden of every image a macOS RunnerPool of the
	// Node's fleet runs. Nil when the fleet has no pools or they could not
	// be listed, which disables the superseded-image rules.
	poolGoldens map[string]struct{}
	// imageRefs holds the full ref of every Pod and pool image, as pulled
	// from its registry and from each mirror. tagRepos holds the repository
	// of every one named by tag, whose digest Tart lists but the ref does
	// not carry.
	imageRefs map[string]struct{}
	tagRepos  map[string]struct{}

	// successions maps the golden of a pool's previous image to the pool's
	// move, and following holds the previous goldens this pass keeps until
	// their successor is pulled (see follow.go).
	successions map[string]succession
	following   map[string]struct{}
}

// superseded reports whether golden is for an image no pool of the fleet
// runs any more.
func (e *expectedSet) superseded(golden string) bool {
	if e.poolGoldens == nil {
		return false
	}
	_, current := e.poolGoldens[golden]
	return !current
}

// keepsImage reports whether the OCI cache entry name is an image a Pod or
// a pool still runs. Without pools to compare against, any image of a
// repository a Pod references is kept, superseded digests included.
func (e *expectedSet) keepsImage(name string) bool {
	repository := ociRepository(name)
	if e.poolGoldens == nil {
		_, want := e.imageRepos[repository]
		return want
	}
	if _, want := e.imageRefs[name]; want {
		return true
	}
	_, want := e.tagRepos[repository]
	return want
}

func (e *expectedSet) addImage(image string, images *ImageSources) {
	repository := ociRepository(image)
	reference := strings.TrimPrefix(image, repository)
	byTag := !strings.HasPrefix(reference, "@")
	for _, repo := range append([]string{repository}, images.mirroredRepositories(repository)...) {
		e.imageRefs[repo+reference] = struct{}{}
		if byTag {
			e.tagRepos[repo] = struct{}{}
		}
	}
}

func (c *Collector) expectedSet(ctx context.Context) (*expectedSet, error) {
	pods := &corev1.PodList{}
	if err := c.K8s.List(ctx, pods, client.MatchingFields{"spec.nodeName": c.NodeName}); err != nil {
		return nil, err
	}
	out := &expectedSet{
		vms:        map[string]struct{}{},
		imageRepos: map[string]struct{}{},
		imageRefs:  map[string]struct{}{},
		tagRepos:   map[string]struct{}{},
		following:  map[string]struct{}{},
	}
	if c.Fleet != "" {
		pools, err := listRunnerPools(ctx, c.K8s)
		if err != nil {
			log.FromContext(ctx).WithName("gc").Error(err, "list runner pools; keeping superseded images for the retention window")
		}
		// A staged golden is an image a pool moves to next: it must not
		// read as superseded before the deploy that moves the pool.
		var upcoming upcomingImages
		if len(pools) > 0 {
			if upcoming, err = listUpcomingImages(ctx, c.K8s); err != nil {
				log.FromContext(ctx).WithName("gc").Error(err, "list upcoming runner images; keeping superseded images for the retention window")
				pools = nil
			}
		}
		for _, pool := range pools {
			if !pool.runsOn(c.Fleet) {
				continue
			}
			if out.poolGoldens == nil {
				out.poolGoldens = map[string]struct{}{}
			}
			images := []string{pool.Spec.Image}
			if next := upcoming.forPool(pool); next != "" {
				images = append(images, next)
			}
			for _, image := range images {
				out.poolGoldens[goldenVMName(image)] = struct{}{}
				out.addImage(image, c.Images)
			}
			if previous := pool.previousImage(); previous != "" && previous != pool.Spec.Image {
				if out.successions == nil {
					out.successions = map[string]succession{}
				}
				out.successions[goldenVMName(previous)] = succession{previous: previous, current: pool.Spec.Image}
			}
		}
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
		repository := ociRepository(pod.Spec.Containers[0].Image)
		out.imageRepos[repository] = struct{}{}
		for _, mirrored := range c.Images.mirroredRepositories(repository) {
			out.imageRepos[mirrored] = struct{}{}
		}
		out.addImage(pod.Spec.Containers[0].Image, c.Images)
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
// images by tag or digest while Tart caches and lists them by digest,
// so the GC has to compare on the repository the two share. A registry port (a
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

// collectContent releases what reaped goldens leave in Tart's content store.
// A stacked golden is a manifest and a small overlay over a read-only base the
// store holds once for every VM and cached image built on it, and deleting the
// golden does not collect the base, so without this a reaped stacked golden
// frees almost nothing. Tart releases that predate the store collect nothing.
func (c *Collector) collectContent(ctx context.Context) {
	if err := c.Tart.CollectContent(ctx); err != nil {
		log.FromContext(ctx).WithName("gc").Error(err, "collect tart content store")
	}
}
