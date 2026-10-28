package cachevolumes

import (
	"context"
	"errors"
	"os"
	"testing"
)

// partialTransfer leaves a partial archive beside the path it is given, as an
// interrupted HTTPTransfer does, until it is told to finish.
type partialTransfer struct {
	testTransfer
	paths  []string
	finish bool
}

func (p *partialTransfer) Download(ctx context.Context, slot Slot, path string) error {
	p.paths = append(p.paths, path)
	if !p.finish {
		_ = os.WriteFile(path+".part", []byte("half"), 0600)
		return errors.New("connection reset")
	}
	return os.WriteFile(path, []byte("restored"), 0600)
}

func TestPrefetchResumesThePreviousAttemptsDownload(t *testing.T) {
	b, _ := newAPFS(t)
	remote := &partialTransfer{}
	b.Transfer = remote
	slot := warmSlot(first, "")
	if err := b.Prefetch(context.Background(), slot); err == nil {
		t.Fatal("an interrupted download installed a master")
	}

	remote.finish = true
	if err := b.Prefetch(context.Background(), slot); err != nil {
		t.Fatal(err)
	}

	if remote.paths[0] != remote.paths[1] {
		t.Fatalf("the retry downloaded to %s, not to %s where the partial archive is", remote.paths[1], remote.paths[0])
	}
	if !b.HasMaster(slot.Identity) {
		t.Fatal("the master was not installed")
	}
}
