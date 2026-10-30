package main

import (
	"context"
	"fmt"
	"testing"
	"testing/synctest"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func TestPrefetchDeduplicatesTheActiveGeneration(t *testing.T) {
	started, release := make(chan struct{}), make(chan struct{})
	finished := make(chan cachevolumes.Observation, 1)
	p := &prefetcher{observe: func(o cachevolumes.Observation) { finished <- o }, restore: func(ctx context.Context, slot cachevolumes.Slot) error {
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
		p := &prefetcher{observe: func(o cachevolumes.Observation) { finished <- o }, restore: func(ctx context.Context, slot cachevolumes.Slot) error {
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
	p := &prefetcher{local: func(identity cachevolumes.Identity) bool { return local[identity.BaseGeneration] }, restore: func(_ context.Context, slot cachevolumes.Slot) error {
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

func TestPrefetchQueuesOtherLineagesAndCoalescesNewerHeads(t *testing.T) {
	started := make(chan cachevolumes.Identity, 4)
	release := make(chan struct{})
	p := &prefetcher{restore: func(_ context.Context, slot cachevolumes.Slot) error {
		started <- slot.Identity
		<-release
		return nil
	}}
	p.start(cachevolumes.Identity{Scope: "a", BaseGeneration: 1})
	<-started
	if !p.start(cachevolumes.Identity{Scope: "b", BaseGeneration: 7}) || !p.start(cachevolumes.Identity{Scope: "b", BaseGeneration: 8}) || !p.start(cachevolumes.Identity{Scope: "a", BaseGeneration: 2}) {
		t.Fatal("lost queued refresh")
	}
	if p.start(cachevolumes.Identity{Scope: "b", BaseGeneration: 7}) {
		t.Fatal("replaced latest queued head with stale head")
	}
	if !p.start(cachevolumes.Identity{Scope: "b", BaseGeneration: 8, ID: "latest-use"}) {
		t.Fatal("did not refresh the queued head's use identity")
	}
	release <- struct{}{}
	if next := <-started; next.Scope != "b" || next.BaseGeneration != 8 || next.ID != "latest-use" {
		t.Fatalf("next = %+v", next)
	}
	release <- struct{}{}
	if next := <-started; next.Scope != "a" || next.BaseGeneration != 2 {
		t.Fatalf("next = %+v", next)
	}
	close(release)
}

func TestPrefetchQueueIsBoundedButStillAcceptsNewerQueuedHeads(t *testing.T) {
	release := make(chan struct{})
	p := &prefetcher{restore: func(context.Context, cachevolumes.Slot) error { <-release; return nil }}
	defer close(release)
	p.start(cachevolumes.Identity{Scope: "active", BaseGeneration: 1})
	for i := range prefetchQueueLimit {
		if !p.start(cachevolumes.Identity{Scope: fmt.Sprint(i), BaseGeneration: 1}) {
			t.Fatal("queue rejected before bound")
		}
	}
	if p.start(cachevolumes.Identity{Scope: "overflow", BaseGeneration: 1}) {
		t.Fatal("unbounded queue")
	}
	if !p.start(cachevolumes.Identity{Scope: "0", BaseGeneration: 2}) {
		t.Fatal("full queue rejected a newer head for an existing lineage")
	}
}
