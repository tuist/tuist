package cachevolumes

import (
	"encoding/json"
	"errors"
	"golang.org/x/sys/unix"
	"io"
	"os"
	"path/filepath"
)

// GuestUsage is what the guest measured when it detached a volume. A guest
// that predates change detection reports every volume as changed.
type GuestUsage struct {
	Used, Capacity int64
	Changed        bool
}

// Guest measurements are telemetry, not authority for host admission. Bind them
// to the lease and bound both file reads and values before retaining them.
func APFSUsage(path, id string, maxCapacity int64) (GuestUsage, error) {
	parent, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return GuestUsage{}, err
	}
	defer parent.Close()
	root, err := parent.OpenRoot(filepath.Base(path))
	if err != nil {
		return GuestUsage{}, err
	}
	defer root.Close()
	f, err := root.OpenFile(".usage", os.O_RDONLY|unix.O_NONBLOCK, 0)
	if err != nil {
		return GuestUsage{}, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return GuestUsage{}, err
	}
	if !info.Mode().IsRegular() || info.Size() > 4096 {
		return GuestUsage{}, errors.New("invalid guest usage file")
	}
	var usage struct {
		ID       string `json:"id"`
		Used     int64  `json:"used_bytes"`
		Capacity int64  `json:"capacity_bytes"`
		Changed  *bool  `json:"changed"`
	}
	if err = json.NewDecoder(io.LimitReader(f, 4096)).Decode(&usage); err != nil {
		return GuestUsage{}, err
	}
	if usage.ID != id || usage.Used < 0 || usage.Capacity <= 0 || usage.Used > usage.Capacity || usage.Capacity > maxCapacity {
		return GuestUsage{}, errors.New("invalid guest usage")
	}
	return GuestUsage{Used: usage.Used, Capacity: usage.Capacity, Changed: usage.Changed == nil || *usage.Changed}, nil
}

func (u GuestUsage) OutOfSpace() bool { return outOfSpace(u.Used, u.Capacity) }

// outOfSpace matches the server's rule for a clone that filled its volume.
func outOfSpace(used, capacity int64) bool { return used*100 >= capacity*99 }
