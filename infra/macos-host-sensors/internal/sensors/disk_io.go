package sensors

import (
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
)

// ProcessIO is one process's disk I/O since it started, as macOS's
// proc_pid_rusage reports it (ri_diskio_bytesread/byteswritten).
type ProcessIO struct {
	PID int
	// Start tells a reused PID from the process that had it before.
	Start uint64
	// Name is the executable's file name.
	Name    string
	Read    uint64
	Written uint64
}

// DiskIO is the bytes a group of processes read from and wrote to disk.
type DiskIO struct {
	Read    uint64 `json:"read"`
	Written uint64 `json:"written"`
}

// DiskIOGroups are the groups processes are counted under, so the series
// stay fixed however many VMs come and go.
var DiskIOGroups = []string{"vm", "tart-kubelet", "tart", "disk-images", "kernel", "other"}

// diskIOGroup names the group a process's I/O counts under. A runner VM's
// disk is written by the Virtualization framework's XPC service, not by the
// `tart run` process that started it.
func diskIOGroup(name string) string {
	switch name {
	case "com.apple.Virtualization.VirtualMachine":
		return "vm"
	case "tart-kubelet":
		return "tart-kubelet"
	case "tart":
		return "tart"
	case "hdiutil", "diskimages-helper", "diskimagesiod":
		return "disk-images"
	case "kernel_task":
		return "kernel"
	}
	return "other"
}

// diskIOState is what one run hands the next: the running totals per group
// and each live process's counters, so a process's bytes are counted once
// however many samples it lives through.
type diskIOState struct {
	Totals    map[string]DiskIO `json:"totals"`
	Processes map[string]DiskIO `json:"processes"`
}

func processKey(p ProcessIO) string {
	return strconv.Itoa(p.PID) + "@" + strconv.FormatUint(p.Start, 10)
}

// accountDiskIO adds what each process read and wrote since the previous
// sample to its group's total. A process absent from the previous sample
// counts from its start, so a VM that boots between two samples is counted
// whole. Without a previous sample the processes only seed the next one:
// counting every process's lifetime at once would put days of I/O into one
// sample. What a process does between the last sample and its exit is lost,
// at most one interval (30 seconds).
func accountDiskIO(prev *diskIOState, procs []ProcessIO) diskIOState {
	next := diskIOState{Totals: map[string]DiskIO{}, Processes: map[string]DiskIO{}}
	for _, g := range DiskIOGroups {
		if prev != nil {
			next.Totals[g] = prev.Totals[g]
		} else {
			next.Totals[g] = DiskIO{}
		}
	}
	for _, p := range procs {
		key := processKey(p)
		next.Processes[key] = DiskIO{Read: p.Read, Written: p.Written}
		if prev == nil {
			continue
		}
		before := prev.Processes[key]
		total := next.Totals[diskIOGroup(p.Name)]
		if p.Read >= before.Read {
			total.Read += p.Read - before.Read
		}
		if p.Written >= before.Written {
			total.Written += p.Written - before.Written
		}
		next.Totals[diskIOGroup(p.Name)] = total
	}
	return next
}

// AccountDiskIO reads every process's disk I/O, adds it to the totals kept in
// statePath and returns them per group. The totals are counters: they only
// restart (from zero) when the state file is lost.
func AccountDiskIO(statePath string) (map[string]DiskIO, error) {
	procs, err := readProcessIO()
	if err != nil {
		return nil, err
	}
	var prev *diskIOState
	data, err := os.ReadFile(statePath)
	switch {
	case err == nil:
		var s diskIOState
		if json.Unmarshal(data, &s) == nil && s.Totals != nil {
			prev = &s
		}
	case !errors.Is(err, fs.ErrNotExist):
		return nil, err
	}
	next := accountDiskIO(prev, procs)
	data, err = json.Marshal(next)
	if err != nil {
		return nil, err
	}
	if err := WriteFile(statePath, data, 0o600); err != nil {
		return nil, err
	}
	if prev == nil {
		// The first sample has nothing to compare with; report the
		// counters from the next one on.
		return nil, nil
	}
	return next.Totals, nil
}

// WriteFile replaces path in one rename, so a reader never sees it half
// written.
func WriteFile(path string, data []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+"-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
