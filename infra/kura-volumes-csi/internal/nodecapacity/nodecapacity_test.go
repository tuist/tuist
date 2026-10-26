package nodecapacity

import (
	"context"
	"errors"
	"log/slog"
	"testing"
)

type fakePatcher struct {
	node    string
	patches []string
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
	p := &fakePatcher{}
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
