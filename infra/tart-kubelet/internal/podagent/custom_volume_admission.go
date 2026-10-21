package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// customCapacity is the size of a volume the server allocated without one.
const customCapacity = 20_000_000_000

func customVolumeBytes(slot cachevolumes.Slot) uint64 {
	return uint64(slot.VolumeSize(customCapacity))
}

// CacheCapacityNodeLabel advertises the cache disk capacity in whole GiB. The
// server subtracts the volumes of the jobs it placed here, attached or not yet,
// and prefers this host for a job only while its volumes fit: admission reserves
// a volume's full capacity, and a second job that cannot get it runs cold.
const CacheCapacityNodeLabel = "tuist.dev/cache-volume-capacity-gib"

// CapacityNodeLabels returns the label advertising the cache disk's capacity
// within its budget, or none while the cache filesystem is not mounted.
func (c *CustomVolumes) CapacityNodeLabels() (map[string]string, error) {
	labels := map[string]string{}
	mounted, err := c.Builtins.backend.isMounted(c.Builtins.Root)
	if err != nil || !mounted {
		return labels, err
	}
	capacity, err := c.Builtins.volumeCapacityBytes()
	if err != nil {
		return nil, err
	}
	labels[CacheCapacityNodeLabel] = strconv.FormatUint(capacity>>30, 10)
	return labels, nil
}

// Custom masters are reclaimed by the shared backend first. If that is not
// enough, unused built-in masters and convergence staging share the same disk
// budget. Keep the full reservation of every writer; CoW blocks may stay pinned
// after a master is removed, so admission must remeasure the filesystem.
func (c *CustomVolumes) reclaim(ctx context.Context, minimum uint64) error {
	release, err := c.guard(ctx)
	if err != nil {
		return err
	}
	defer release()
	if _, err := c.freeBytesLocked(); err != nil {
		return err
	}
	want := minimum + uint64(len(c.Builtins.reserved))*c.Builtins.capBytes() + c.reservedBytes()
	_, err = c.Builtins.admitBesideConvergenceLocked(want, masterKey{})
	if errors.Is(err, errNoRoom) && c.Builtins.dropConvergeStagingLocked() {
		_, err = c.Builtins.ensureFreeLocked(want, masterKey{})
	}
	// Idle checkout copies are rebuilt from the next jobs' exports, so they go before
	// a job loses its volume.
	if errors.Is(err, errNoRoom) && c.Checkouts.Evict(func() bool {
		free, freeErr := c.freeBytesLocked()
		return freeErr == nil && free >= minimum
	}) {
		_, err = c.Builtins.ensureFreeLocked(want, masterKey{})
	}
	if errors.Is(err, errNoRoom) {
		return cachevolumes.ErrCapacity
	}
	return err
}

// Called under the built-in admission lock. Filesystem free space already
// includes allocated blocks; only running writers need additional headroom.
func (c *CustomVolumes) reservedBytes() uint64 {
	var total uint64
	for id, slot := range c.reservations {
		// A clone reports the master's shared blocks as allocated; reserve its budget.
		if slot.Kind == cachevolumes.KindCheckout {
			total += cachevolumes.CheckoutGrowthBytes
			continue
		}
		if slot.State != "active" {
			total += customAdmissionBytes(slot)
			continue
		}
		allocated, err := c.Builtins.backend.allocatedBytes(filepath.Join(c.Root, "images", id+".img"))
		if err != nil {
			allocated = 0
		}
		if size := customVolumeBytes(slot); allocated < size {
			total += size - allocated
		}
	}
	return total
}

// A job clones a local master or starts empty, so it needs one image of room.
// Only a prefetch downloads, keeping its archive beside the restored image:
// twice the head's used bytes, or twice the volume when that is unknown.
func customAdmissionBytes(slot cachevolumes.Slot) uint64 {
	if slot.Kind == cachevolumes.KindCheckout {
		return cachevolumes.CheckoutGrowthBytes
	}
	if slot.ID == cachevolumes.PrefetchReservation {
		return uint64(slot.RestoreBytes(customCapacity))
	}
	return customVolumeBytes(slot)
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
	if free < customAdmissionBytes(slot) && slot.ID != cachevolumes.PrefetchReservation && c.displaceSpareLocked() {
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
		c.Builtins.mu.Lock()
		defer c.Builtins.mu.Unlock()
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
	c.Builtins.mu.Lock()
	before := make(map[string]cachevolumes.Slot, len(c.reservations))
	for id, slot := range c.reservations {
		before[id] = slot
	}
	c.Builtins.mu.Unlock()
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
		if _, err := os.Stat(filepath.Join(c.Root, "images", slot.ID+".img")); os.IsNotExist(err) {
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
	c.Builtins.mu.Lock()
	defer c.Builtins.mu.Unlock()
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
func (c *CustomVolumes) prefetchSpare(ctx context.Context, run func(context.Context) error) error {
	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	c.Builtins.mu.Lock()
	c.spare = cancel
	c.Builtins.mu.Unlock()
	defer func() {
		c.Builtins.mu.Lock()
		c.spare = nil
		c.Builtins.mu.Unlock()
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
	return c.displaceSpareLocked()
}

// displaceSpareLocked cancels a background prefetch and drops its reservation,
// so built-in and custom job admission spend that space before evicting a
// master. Bytes it already downloaded stay until it unwinds; free space already
// reflects them. Requires Builtins.mu.
func (c *CustomVolumes) displaceSpareLocked() bool {
	if c.spare == nil {
		return false
	}
	c.spare(errSpareDisplaced)
	c.spare = nil
	delete(c.reservations, cachevolumes.PrefetchReservation)
	log.Log.WithName("custom-cache-volumes").Info("admission cancelled a background prefetch to make room for a job")
	return true
}
