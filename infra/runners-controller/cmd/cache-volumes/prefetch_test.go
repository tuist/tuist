package main

import (
	"context"
	"errors"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func TestPrefetchHasOneWorkerNoQueueAndItsOwnDeadline(t *testing.T) {
	started := make(chan struct{})
	finished := make(chan cachevolumes.Observation, 1)
	p := &prefetcher{slots: make(chan struct{}, 1), budget: 20 * time.Millisecond, observe: func(o cachevolumes.Observation) { finished <- o }, restore: func(ctx context.Context, slot cachevolumes.Slot) error {
		close(started)
		<-ctx.Done()
		return ctx.Err()
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
	select {
	case result := <-finished:
		if !errors.Is(result.Err, context.DeadlineExceeded) {
			t.Fatal(result)
		}
	case <-time.After(time.Second):
		t.Fatal("unbounded prefetch")
	}
}

func TestPrefetchSkipsAMasterAlreadyOnTheHost(t *testing.T) {
	restored := make(chan cachevolumes.Slot, 1)
	local := map[int64]bool{1: true}
	p := &prefetcher{slots: make(chan struct{}, 1), budget: time.Second, local: func(identity cachevolumes.Identity) bool { return local[identity.BaseGeneration] }, restore: func(_ context.Context, slot cachevolumes.Slot) error {
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
