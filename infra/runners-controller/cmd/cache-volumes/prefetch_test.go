package main

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/runners-controller/internal/cachevolumes"
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
