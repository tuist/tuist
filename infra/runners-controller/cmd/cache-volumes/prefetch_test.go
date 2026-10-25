package main

import (
	"context"
	"testing"
	"testing/synctest"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func TestPrefetchHasOneWorkerAndNoQueue(t *testing.T) {
	started, release := make(chan struct{}), make(chan struct{})
	finished := make(chan cachevolumes.Observation, 1)
	p := &prefetcher{slots: make(chan struct{}, 1), observe: func(o cachevolumes.Observation) { finished <- o }, restore: func(ctx context.Context, slot cachevolumes.Slot) error {
		close(started)
		<-release
		return nil
	}}
	if p.start(cachevolumes.Identity{}) {
		t.Fatal("prefetched an empty volume")
	}
	if !p.start(cachevolumes.Identity{BaseGeneration: 1}) {
		t.Fatal("did not start")
	}
	<-started
	if p.start(cachevolumes.Identity{BaseGeneration: 1}) {
		t.Fatal("queued concurrent prefetch")
	}
	close(release)
	if result := <-finished; result.Err != nil {
		t.Fatal(result)
	}
}

func TestPrefetchKeepsADownloadThatProgressesPastItsOldBudget(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		finished := make(chan cachevolumes.Observation, 1)
		p := &prefetcher{slots: make(chan struct{}, 1), observe: func(o cachevolumes.Observation) { finished <- o }, restore: func(ctx context.Context, slot cachevolumes.Slot) error {
			// A byte every second for five minutes.
			for range 5 * 60 {
				select {
				case <-ctx.Done():
					return ctx.Err()
				case <-time.After(time.Second):
				}
			}
			return nil
		}}

		p.start(cachevolumes.Identity{BaseGeneration: 1})

		if result := <-finished; result.Err != nil {
			t.Fatal("a prefetch still receiving bytes was cut off:", result.Err)
		}
	})
}

func TestPrefetchSkipsAMasterAlreadyOnTheHost(t *testing.T) {
	restored := make(chan cachevolumes.Slot, 1)
	local := map[int64]bool{1: true}
	p := &prefetcher{slots: make(chan struct{}, 1), local: func(identity cachevolumes.Identity) bool { return local[identity.BaseGeneration] }, restore: func(_ context.Context, slot cachevolumes.Slot) error {
		restored <- slot
		return nil
	}}

	if p.start(cachevolumes.Identity{BaseGeneration: 1}) {
		t.Fatal("fetched a master the job cloned locally")
	}
	if !p.start(cachevolumes.Identity{BaseGeneration: 2}) {
		t.Fatal("did not fetch the saved version a job attached without")
	}
	if slot := <-restored; slot.BaseGeneration != 2 {
		t.Fatal(slot)
	}
}
