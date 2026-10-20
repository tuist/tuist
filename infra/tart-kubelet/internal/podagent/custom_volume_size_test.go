package podagent

import (
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func TestCustomReservationsFollowTheAllocatedVolumeSize(t *testing.T) {
	m, _ := m2L(t)
	c := &CustomVolumes{Builtins: m, reservations: map[string]cachevolumes.Slot{}}
	restoring := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", BaseGeneration: 1, VolumeBytes: 30_000_000_000}}
	cold := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "22222222-2222-4222-8222-222222222222", VolumeBytes: 30_000_000_000}}
	c.reservations[restoring.ID] = restoring
	c.reservations[cold.ID] = cold

	// A restore holds an archive beside the expanded image; a cold volume holds the image.
	if got, want := c.reservedBytes(), uint64(2*30_000_000_000+30_000_000_000); got != want {
		t.Fatalf("reserved %d bytes, want %d", got, want)
	}
}
