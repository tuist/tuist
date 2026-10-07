package podagent

import (
	"context"
	"os"
	"path/filepath"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const customCapacity = 20_000_000_000

// Called under the built-in admission lock. Filesystem free space already
// includes allocated blocks; only running writers need additional headroom.
func (c *CustomVolumes) reservedBytes() uint64 {
	var total uint64
	for id, slot := range c.reservations {
		// Restore can temporarily retain both the archive and expanded master.
		if slot.State != "active" {
			total += 2 * customCapacity
			continue
		}
		allocated, err := c.Builtins.backend.allocatedBytes(filepath.Join(c.Root, "images", id+".img"))
		if err != nil {
			allocated = 0
		}
		if allocated < customCapacity {
			total += customCapacity - allocated
		}
	}
	return total
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
	if free < 40_000_000_000 {
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
