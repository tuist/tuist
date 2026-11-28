//go:build darwin

package sensors

import (
	"encoding/binary"
	"fmt"
	"path/filepath"
	"unsafe"

	"github.com/ebitengine/purego"
)

const (
	// RUSAGE_INFO_V2 is the first rusage_info version with the disk I/O
	// counters. Its struct: a 16-byte UUID, then uint64 fields, of which
	// ri_proc_start_abstime is the 9th and ri_diskio_bytesread and
	// ri_diskio_byteswritten the 17th and 18th.
	rusageInfoV2           = 2
	rusageOffsetStart      = 16 + 8*8
	rusageOffsetDiskRead   = 16 + 16*8
	rusageOffsetDiskWrite  = 16 + 17*8
	rusageInfoV2Size       = 16 + 18*8
	procPIDPathInfoMaxSize = 4096
	procNameMaxSize        = 2 * 16
)

// readProcessIO reads every process's disk I/O through libproc. Another
// user's processes need root, which the launchd daemon runs as; a process
// that exits while it is read is skipped.
func readProcessIO() ([]ProcessIO, error) {
	lib, err := purego.Dlopen("/usr/lib/libSystem.B.dylib", purego.RTLD_NOW|purego.RTLD_GLOBAL)
	if err != nil {
		return nil, err
	}
	var (
		listAllPIDs func(buffer unsafe.Pointer, size int32) int32
		pidPath     func(pid int32, buffer unsafe.Pointer, size uint32) int32
		name        func(pid int32, buffer unsafe.Pointer, size uint32) int32
		pidRusage   func(pid int32, flavor int32, buffer unsafe.Pointer) int32
	)
	for _, fn := range []struct {
		ptr  any
		name string
	}{
		{&listAllPIDs, "proc_listallpids"},
		{&pidPath, "proc_pidpath"},
		{&name, "proc_name"},
		{&pidRusage, "proc_pid_rusage"},
	} {
		if _, err := purego.Dlsym(lib, fn.name); err != nil {
			return nil, fmt.Errorf("%s: %w", fn.name, err)
		}
		purego.RegisterLibFunc(fn.ptr, lib, fn.name)
	}

	count := listAllPIDs(nil, 0)
	if count <= 0 {
		return nil, fmt.Errorf("proc_listallpids returned %d", count)
	}
	// Room for processes started since the count.
	pids := make([]int32, int(count)+64)
	n := listAllPIDs(unsafe.Pointer(&pids[0]), int32(len(pids)*4))
	if n <= 0 {
		return nil, fmt.Errorf("proc_listallpids returned %d", n)
	}
	pids = pids[:min(int(n), len(pids))]

	var (
		usage [rusageInfoV2Size]byte
		path  [procPIDPathInfoMaxSize]byte
		short [procNameMaxSize + 1]byte
		procs []ProcessIO
	)
	for _, pid := range pids {
		if pidRusage(pid, rusageInfoV2, unsafe.Pointer(&usage[0])) != 0 {
			continue
		}
		var exe string
		if l := pidPath(pid, unsafe.Pointer(&path[0]), uint32(len(path))); l > 0 {
			exe = filepath.Base(string(path[:l]))
		} else if l := name(pid, unsafe.Pointer(&short[0]), uint32(len(short))); l > 0 {
			// kernel_task has no executable path.
			exe = string(short[:l])
		}
		procs = append(procs, ProcessIO{
			PID:     int(pid),
			Start:   binary.LittleEndian.Uint64(usage[rusageOffsetStart:]),
			Name:    exe,
			Read:    binary.LittleEndian.Uint64(usage[rusageOffsetDiskRead:]),
			Written: binary.LittleEndian.Uint64(usage[rusageOffsetDiskWrite:]),
		})
	}
	return procs, nil
}
