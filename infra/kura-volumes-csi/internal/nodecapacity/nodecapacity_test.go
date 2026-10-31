package nodecapacity

import (
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"
)

func TestObservationHasDeadline(t *testing.T) {
	p := &fakePatcher{}
	err := advertiser(p, func(ctx context.Context) (int64, bool, error) {
		deadline, ok := ctx.Deadline()
		if !ok || time.Until(deadline) > 45*time.Second {
			t.Fatal("unbounded capacity observation")
		}
		return 0, false, nil
	}).Once(context.Background())
	if err != nil {
		t.Fatal(err)
	}
}

type fakePatcher struct {
	node    string
	patches []string
	current string
	present bool
	readErr error
}

func (f *fakePatcher) PatchNodeStatus(_ context.Context, node string, patch []byte) error {
	f.node = node
	f.patches = append(f.patches, string(patch))
	return nil
}

func advertiser(p *fakePatcher, measure Measure) *Advertiser {
	return &Advertiser{Node: "node-a", Measure: measure, Patcher: p, Logger: slog.New(slog.DiscardHandler)}
}

func TestOnceAdvertisesTheVolumeGroupRoom(t *testing.T) {
	p := &fakePatcher{}
	err := advertiser(p, func(context.Context) (int64, bool, error) { return 429496729600, true, nil }).Once(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if p.node != "node-a" {
		t.Errorf("patched node %q", p.node)
	}
	if want := `{"status":{"capacity":{"tuist.dev/kura-disk":"429496729600"}}}`; p.patches[0] != want {
		t.Errorf("patch = %s, want %s", p.patches[0], want)
	}
}

func TestOnceRemovesTheResourceWithoutAVolumeGroup(t *testing.T) {
	p := &fakePatcher{current: "1Gi", present: true}
	err := advertiser(p, func(context.Context) (int64, bool, error) { return 0, false, nil }).Once(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if want := `{"status":{"capacity":{"tuist.dev/kura-disk":null}}}`; p.patches[0] != want {
		t.Errorf("patch = %s, want %s", p.patches[0], want)
	}
}

func TestOncePatchesNothingWhenMeasuringFails(t *testing.T) {
	p := &fakePatcher{}
	err := advertiser(p, func(context.Context) (int64, bool, error) { return 0, false, errors.New("lvm") }).Once(context.Background())
	if err == nil || len(p.patches) != 0 {
		t.Fatalf("err = %v, patches = %v; want an error and no patch", err, p.patches)
	}
}

func (f *fakePatcher) NodeCapacity(context.Context, string) (string, bool, error) {
	return f.current, f.present, f.readErr
}

func TestOnceSkipsAnUnchangedAdvertisement(t *testing.T) {
	tests := []struct {
		name      string
		current   string
		present   bool
		readErr   error
		capacity  int64
		available bool
		wantPatch bool
	}{
		{name: "same bytes in canonical form", current: "400Gi", present: true, capacity: 400 << 30, available: true},
		{name: "same plain bytes", current: "429496729600", present: true, capacity: 400 << 30, available: true},
		{name: "same decimal suffix", current: "5k", present: true, capacity: 5000, available: true},
		{name: "already withdrawn", capacity: 0, available: false},
		{name: "changed", current: "399Gi", present: true, capacity: 400 << 30, available: true, wantPatch: true},
		{name: "missing after node re-registration", capacity: 400 << 30, available: true, wantPatch: true},
		{name: "still present after withdrawal", current: "1Gi", present: true, available: false, wantPatch: true},
		{name: "unparseable current value", current: "1.5Gi", present: true, capacity: 1 << 30, available: true, wantPatch: true},
		{name: "unreadable node", readErr: errors.New("apiserver"), capacity: 1 << 30, available: true, wantPatch: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := &fakePatcher{current: tt.current, present: tt.present, readErr: tt.readErr}
			err := advertiser(p, func(context.Context) (int64, bool, error) { return tt.capacity, tt.available, nil }).Once(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			if got := len(p.patches) == 1; got != tt.wantPatch {
				t.Fatalf("patched = %v, want %v (%v)", got, tt.wantPatch, p.patches)
			}
		})
	}
}
