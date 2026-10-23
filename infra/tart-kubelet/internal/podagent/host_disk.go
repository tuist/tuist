package podagent

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// HostDisk tells a host disk that has never held a runner image from one that
// holds none right now. A host reinstalled in place keeps its Node but comes
// back with an erased disk, while an idle host can also hold no golden once a
// release supersedes its images. The marker it records the first time it holds
// a golden is gone only when the disk was erased.
type HostDisk struct {
	Tart       *tart.Client
	MarkerPath string
}

// Fresh reports whether the disk has never held a golden: no marker and no
// golden now. A host that holds a golden but has no marker yet records one.
func (h *HostDisk) Fresh(ctx context.Context) (bool, error) {
	if _, err := os.Stat(h.MarkerPath); err == nil {
		return false, nil
	} else if !errors.Is(err, fs.ErrNotExist) {
		return false, err
	}
	labels, err := GoldenNodeLabels(ctx, h.Tart)
	if err != nil {
		return false, err
	}
	if len(labels) > 0 {
		return false, h.Record()
	}
	return true, nil
}

// Record notes that the disk holds a golden.
func (h *HostDisk) Record() error {
	if _, err := os.Stat(h.MarkerPath); err == nil {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(h.MarkerPath), 0o755); err != nil {
		return err
	}
	return os.WriteFile(h.MarkerPath, nil, 0o644)
}
