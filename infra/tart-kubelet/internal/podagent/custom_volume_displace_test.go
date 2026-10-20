package podagent

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// holdSparePrefetch starts a background prefetch that reserves its space and
// then downloads until it is cancelled, and returns its eventual error.
func holdSparePrefetch(t *testing.T, c *CustomVolumes) <-chan error {
	t.Helper()
	reserved := make(chan error, 1)
	done := make(chan error, 1)
	go func() {
		done <- c.prefetchSpare(context.Background(), func(ctx context.Context) error {
			finish, err := c.reserve(ctx, cachevolumes.Slot{Identity: cachevolumes.Identity{ID: cachevolumes.PrefetchReservation, BaseGeneration: 1}})
			reserved <- err
			if err != nil {
				return err
			}
			defer finish(false)
			<-ctx.Done()
			return ctx.Err()
		})
	}()
	if err := <-reserved; err != nil {
		t.Fatal(err)
	}
	if got := c.reservedBytes(); got != 2*customCapacity {
		t.Fatalf("background prefetch reserved %d bytes", got)
	}
	return done
}

func requireDisplaced(t *testing.T, c *CustomVolumes, done <-chan error) {
	t.Helper()
	c.Builtins.mu.Lock()
	_, held := c.reservations[cachevolumes.PrefetchReservation]
	c.Builtins.mu.Unlock()
	if held {
		t.Fatal("admission left the background prefetch's reservation counting")
	}
	err := <-done
	if !errors.Is(err, errSpareDisplaced) || cachevolumes.Result(err) != "cancelled" {
		t.Fatalf("background prefetch ended with %v", err)
	}
}

// On an M2-L with one 25 GiB master, a job's 30 GiB branch fits beside the
// master but not beside a background prefetch's 40 GB as well. The prefetch is
// speculative, so it gives way; the master jobs clone from stays.
func TestBuiltinAdmissionCancelsABackgroundPrefetchBeforeEvicting(t *testing.T) {
	m, _ := m2L(t)
	seedMaster(t, m, "3")
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	m.CustomReserved = c.reservedBytes
	m.DisplaceCustom = c.displaceSpareLocked
	done := holdSparePrefetch(t, c)

	att := mustAllocate(t, m, "vm-7")
	if _, _, err := m.Materialize(att, "7"); err != nil {
		t.Fatal(err)
	}
	if !masterExists(m, "3") {
		t.Fatal("evicted a master to keep a background prefetch's reservation")
	}
	requireDisplaced(t, c, done)
}

func TestCustomAdmissionCancelsABackgroundPrefetch(t *testing.T) {
	m, _ := m2L(t)
	seedMaster(t, m, "3")
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	done := holdSparePrefetch(t, c)

	finish, err := c.reserve(context.Background(), cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111"}})
	if err != nil {
		t.Fatalf("job declined beside a background prefetch: %v", err)
	}
	defer finish(false)
	requireDisplaced(t, c, done)
	if !masterExists(m, "3") {
		t.Fatal("custom admission removed a built-in master")
	}
}

// A job that fits beside the prefetch leaves it running.
func TestAdmissionLeavesABackgroundPrefetchThatFits(t *testing.T) {
	m, _ := m2L(t)
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	m.CustomReserved = c.reservedBytes
	m.DisplaceCustom = c.displaceSpareLocked
	done := holdSparePrefetch(t, c)

	att := mustAllocate(t, m, "vm-7")
	if _, _, err := m.Materialize(att, "7"); err != nil {
		t.Fatal(err)
	}
	m.mu.Lock()
	running := c.spare != nil
	cancel := c.spare
	m.mu.Unlock()
	if !running {
		t.Fatal("cancelled a background prefetch that fit beside the job")
	}
	cancel(context.Canceled)
	if err := <-done; errors.Is(err, errSpareDisplaced) {
		t.Fatal(err)
	}
}
