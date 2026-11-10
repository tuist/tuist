package podagent

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// customCapacity is the size of a volume the server allocated without one.
const customCapacity = 20_000_000_000

// customExpectedBytes is what a job's copy is admitted with and, while its VM
// runs, what its growth is reserved up to (Identity.ExpectedBytes). runner-cache
// admits the same bytes; if they disagree, the second check rejects what the
// first admitted.
func customExpectedBytes(slot cachevolumes.Slot) uint64 {
	return uint64(slot.ExpectedBytes(customCapacity))
}

// CacheCapacityNodeLabel advertises the cache disk capacity in whole GiB. The
// server subtracts the volumes of the jobs it placed here, attached or not yet,
// and prefers this host for a job only while its volumes fit: admission reserves
// what each volume is expected to write (customExpectedBytes), and a second job
// that cannot get it runs cold.
const CacheCapacityNodeLabel = "tuist.dev/cache-volume-capacity-gib"

// CapacityNodeLabels returns the label advertising the cache disk's capacity
// within its budget, or none while the cache filesystem is not mounted.
func (c *CustomVolumes) CapacityNodeLabels() (map[string]string, error) {
	labels := map[string]string{}
	mounted, err := c.Space.backend.isMounted(c.Space.Root)
	if err != nil || !mounted {
		return labels, err
	}
	capacity, err := c.Space.volumeCapacityBytes()
	if err != nil {
		return nil, err
	}
	labels[CacheCapacityNodeLabel] = strconv.FormatUint(capacity>>30, 10)
	return labels, nil
}

// reclaim evicts idle checkout copies, which the next jobs' exports rebuild, before a job loses its volume.
func (c *CustomVolumes) reclaim(ctx context.Context, minimum uint64) error {
	release, err := c.guard(ctx)
	if err != nil {
		return err
	}
	defer release()
	free, err := c.freeBytesLocked()
	if err != nil || free >= minimum {
		return err
	}
	c.Checkouts.Evict(func() bool {
		free, err = c.freeBytesLocked()
		return err == nil && free >= minimum
	})
	if free, err = c.freeBytesLocked(); err != nil {
		return err
	}
	if free < minimum {
		return cachevolumes.ErrCapacity
	}
	return nil
}

// Called under the admission lock. Filesystem free space already
// includes allocated blocks; only running writers need additional headroom.
func (c *CustomVolumes) reservedBytes() uint64 {
	var total uint64
	for _, slot := range c.reservations {
		// A clone reports the master's shared blocks as allocated; reserve its budget.
		if slot.Kind == cachevolumes.KindCheckout {
			total += cachevolumes.CheckoutGrowthBytes
			continue
		}
		if slot.State != "active" {
			total += customAdmissionBytes(slot)
			continue
		}
		allocated, err := c.Space.backend.allocatedBytes(cachevolumes.APFSBranchFile(c.Root, slot))
		if err != nil {
			allocated = 0
		}
		if size := customExpectedBytes(slot); allocated < size {
			total += size - allocated
		}
	}
	return total
}

// A job clones a local master or starts empty, so it needs what it is expected
// to write. Only a prefetch downloads, keeping its archive beside the restored image:
// twice the head's used bytes, or twice the volume when that is unknown.
func customAdmissionBytes(slot cachevolumes.Slot) uint64 {
	if slot.Kind == cachevolumes.KindCheckout {
		return cachevolumes.CheckoutGrowthBytes
	}
	if slot.ID == cachevolumes.PrefetchReservation {
		return uint64(slot.RestoreBytes(customCapacity))
	}
	return customExpectedBytes(slot)
}

func (c *CustomVolumes) reserve(ctx context.Context, slot cachevolumes.Slot) (func(bool), error) {
	release, err := c.guard(ctx)
	if err != nil {
		return nil, err
	}
	defer release()
	free, err := c.freeBytesLocked()
	if err != nil {
		return nil, err
	}
	if free < customAdmissionBytes(slot) && slot.ID != cachevolumes.PrefetchReservation && c.displaceSpareLocked(cachevolumes.SubjectOf(slot).ForFields()...) {
		if free, err = c.freeBytesLocked(); err != nil {
			return nil, err
		}
	}
	if free < customAdmissionBytes(slot) {
		return nil, cachevolumes.ErrCapacity
	}
	if c.reservations == nil {
		c.reservations = make(map[string]cachevolumes.Slot)
	}
	slot.State = "allocated"
	c.reservations[slot.ID] = slot
	return func(retain bool) {
		c.Space.mu.Lock()
		defer c.Space.mu.Unlock()
		if retain {
			slot.State = "active"
			c.reservations[slot.ID] = slot
		} else {
			delete(c.reservations, slot.ID)
		}
	}, nil
}

// Recover admission after restart and stop reserving growth once a VM stops,
// even if its branch is still waiting for publication or an upload retry.
func (c *CustomVolumes) refreshReservations(ctx context.Context) error {
	c.Space.mu.Lock()
	before := make(map[string]cachevolumes.Slot, len(c.reservations))
	for id, slot := range c.reservations {
		before[id] = slot
	}
	c.Space.mu.Unlock()
	slots, err := c.Store.Snapshot()
	if err != nil {
		return err
	}
	live := make(map[string]cachevolumes.Slot)
	running := make(map[string]bool)
	probe := c.Running
	if probe == nil {
		probe = c.Tart.IsRunning
	}
	for _, slot := range slots {
		if slot.State == "deleted" {
			continue
		}
		if !cachevolumes.APFSHasBranch(c.Root, slot) {
			continue
		}
		vm := VMNameForPod(&corev1.Pod{ObjectMeta: metav1.ObjectMeta{Namespace: c.Namespace, Name: slot.PodName}})
		active, checked := running[vm]
		if !checked {
			active, err = probe(ctx, vm)
			if err != nil {
				active = true
			}
			running[vm] = active
		}
		if active {
			live[slot.ID] = slot
		}
	}
	c.Space.mu.Lock()
	defer c.Space.mu.Unlock()
	if c.reservations == nil {
		c.reservations = make(map[string]cachevolumes.Slot)
	}
	// Never overwrite admission performed while the runtime probes were running.
	// Pending creation and prefetch own their reservation until their callback.
	for id, slot := range before {
		if current, ok := c.reservations[id]; !ok || current != slot || slot.State != "active" {
			continue
		}
		if _, running := live[id]; !running {
			delete(c.reservations, id)
		}
	}
	for id, slot := range live {
		if _, exists := c.reservations[id]; !exists {
			c.reservations[id] = slot
		}
	}
	return nil
}

var errSpareDisplaced = errors.New("background prefetch gave way to a job")

// prefetchSpare runs a download the server listed for this host so that job
// admission can cancel it (displaceSpareLocked). The prefetcher runs one
// download at a time, so at most one is registered.
func (c *CustomVolumes) prefetchSpare(ctx context.Context, scope string, run func(context.Context) error) error {
	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	c.Space.mu.Lock()
	c.spare, c.spareScope = cancel, scope
	c.Space.mu.Unlock()
	defer func() {
		c.Space.mu.Lock()
		c.spare, c.spareScope = nil, ""
		c.Space.mu.Unlock()
	}()
	err := run(ctx)
	if err != nil && errors.Is(context.Cause(ctx), errSpareDisplaced) {
		return fmt.Errorf("%w: %w", errSpareDisplaced, context.Canceled)
	}
	return err
}

func (c *CustomVolumes) displaceSpare(ctx context.Context) bool {
	release, err := c.guard(ctx)
	if err != nil {
		return false
	}
	defer release()
	return c.displaceSpareLocked(cachevolumes.SubjectFrom(ctx).ForFields()...)
}

// displaceSpareLocked cancels a background prefetch and drops its reservation,
// so job admission spends that space before evicting a
// master. Bytes it already downloaded stay until it unwinds; free space already
// reflects them. forFields name what the room is for. Requires Space.mu.
func (c *CustomVolumes) displaceSpareLocked(forFields ...any) bool {
	if c.spare == nil {
		return false
	}
	c.spare(errSpareDisplaced)
	scope := c.spareScope
	c.spare, c.spareScope = nil, ""
	delete(c.reservations, cachevolumes.PrefetchReservation)
	log.Log.WithName("custom-cache-volumes").Info("admission cancelled a background prefetch to make room for a job", append([]any{"scope", scope}, forFields...)...)
	return true
}

// customPressureBytes is how close to the cache filesystem's hard limit
// (hardFreeBytes) running branches are withheld from publication.
const customPressureBytes = 2_000_000_000

// Admission reserves what a job is expected to write, not its capacity, so jobs
// can write past their reservations. Between the admission budget and the APFS
// quota they only crowd out later admissions, and relieve gives the space back.
// Near the quota a write may fail on the host without the guest noticing, so
// notePressure withholds every running branch from publication.
func (c *CustomVolumes) notePressure(ctx context.Context) {
	if c.images == nil {
		return
	}
	free, err := c.Space.hardFreeBytes()
	if err != nil || free >= customPressureBytes {
		return
	}
	release, err := c.guard(ctx)
	if err != nil {
		return
	}
	defer release()
	for id, slot := range c.reservations {
		if id == cachevolumes.PrefetchReservation || slot.Kind == cachevolumes.KindCheckout {
			continue
		}
		if err := c.images.MarkPressure(slot); err != nil {
			log.FromContext(ctx).Error(err, "withhold custom cache branch under disk pressure", "use", id)
		}
	}
}

// relieve evicts idle custom masters once running jobs have written past what
// admission left free, so later jobs are admitted again within the budget.
func (c *CustomVolumes) relieve(ctx context.Context) {
	if c.images == nil {
		return
	}
	evicted, err := c.images.Relieve(ctx, 1)
	if err != nil {
		log.FromContext(ctx).Error(err, "relieve custom cache pressure")
	} else if evicted > 0 {
		log.FromContext(ctx).Info("jobs outgrew their cache reservations; evicted idle custom masters", "count", evicted)
	}
}
