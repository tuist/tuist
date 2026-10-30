package podagent

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// spareScope is the scope the held background prefetch restores.
var spareScope = strings.Repeat("d", 64)

// holdSparePrefetch starts a background prefetch that reserves its space and
// then downloads until it is cancelled, and returns its eventual error.
func holdSparePrefetch(t *testing.T, c *CustomVolumes) <-chan error {
	t.Helper()
	reserved := make(chan error, 1)
	done := make(chan error, 1)
	go func() {
		done <- c.prefetchSpare(context.Background(), spareScope, func(ctx context.Context) error {
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
	c.Space.mu.Lock()
	_, held := c.reservations[cachevolumes.PrefetchReservation]
	c.Space.mu.Unlock()
	if held {
		t.Fatal("admission left the background prefetch's reservation counting")
	}
	err := <-done
	if !errors.Is(err, errSpareDisplaced) || cachevolumes.Result(err) != "cancelled" {
		t.Fatalf("background prefetch ended with %v", err)
	}
}

func TestCustomAdmissionCancelsABackgroundPrefetch(t *testing.T) {
	logs := captureLogs(t)
	m, be := m2L(t)
	be.inUse = 25 * gib
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m}
	done := holdSparePrefetch(t, c)

	finish, err := c.reserve(context.Background(), cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", HeadSizeBytes: customCapacity}})
	if err != nil {
		t.Fatalf("job declined beside a background prefetch: %v", err)
	}
	defer finish(false)
	requireDisplaced(t, c, done)
	requireLogged(t, logs(), "admission cancelled a background prefetch", "scope="+spareScope, "for_use=11111111-1111-4111-8111-111111111111", "for_kind=custom")
}

// A job that fits beside the prefetch leaves it running.
func TestAdmissionLeavesABackgroundPrefetchThatFits(t *testing.T) {
	m, _ := m2L(t)
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m}
	done := holdSparePrefetch(t, c)

	finish, err := c.reserve(context.Background(), cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", HeadSizeBytes: customCapacity}})
	if err != nil {
		t.Fatal(err)
	}
	defer finish(false)
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

// requireLogged fails unless one line holds every part.
func requireLogged(t *testing.T, lines []string, parts ...string) {
	t.Helper()
	for _, line := range lines {
		found := true
		for _, part := range parts {
			found = found && strings.Contains(line, part)
		}
		if found {
			return
		}
	}
	t.Fatalf("no line with %q in %q", parts, lines)
}
