package cachevolumes

import (
	"encoding/json"
	"errors"
	"golang.org/x/sys/unix"
	"io"
	"os"
	"path/filepath"
)

// Guest measurements are telemetry, not authority for host admission. Bind them
// to the lease and bound both file reads and values before retaining them.
func APFSUsage(path, id string, maxCapacity int64) (int64, int64, error) {
	parent, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return 0, 0, err
	}
	defer parent.Close()
	root, err := parent.OpenRoot(filepath.Base(path))
	if err != nil {
		return 0, 0, err
	}
	defer root.Close()
	f, err := root.OpenFile(".usage", os.O_RDONLY|unix.O_NONBLOCK, 0)
	if err != nil {
		return 0, 0, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return 0, 0, err
	}
	if !info.Mode().IsRegular() || info.Size() > 4096 {
		return 0, 0, errors.New("invalid guest usage file")
	}
	var usage struct {
		ID       string `json:"id"`
		Used     int64  `json:"used_bytes"`
		Capacity int64  `json:"capacity_bytes"`
	}
	if err = json.NewDecoder(io.LimitReader(f, 4096)).Decode(&usage); err != nil {
		return 0, 0, err
	}
	if usage.ID != id || usage.Used < 0 || usage.Capacity <= 0 || usage.Used > usage.Capacity || usage.Capacity > maxCapacity {
		return 0, 0, errors.New("invalid guest usage")
	}
	return usage.Used, usage.Capacity, nil
}
