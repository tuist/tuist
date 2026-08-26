// Package hostdisk reports the tart-kubelet host's root-volume usage.
//
// Every Tart artifact — golden base images and running clones — lives on
// the Mac mini's root APFS container, so a fill there silently breaks the
// CAPI operator's SSH-driven config updates ("No space left on device")
// while the Node still reports Ready. Two callers measure it through here:
// the golden-image GC (podagent), which reclaims bases before the disk
// fills, and the Node's DiskPressure + ephemeral-storage reporting
// (nodeagent), which makes a fill visible to the scheduler and alerting.
package hostdisk

import "golang.org/x/sys/unix"

// Stats is a point-in-time root-volume measurement.
type Stats struct {
	TotalBytes uint64
	FreeBytes  uint64 // available to the caller (statfs f_bavail)
}

// FreePercent is FreeBytes as a percentage of TotalBytes. It returns 100
// when the total is unknown so a bad measurement never reads as "full"
// and trips a reclaim or DiskPressure on a false signal.
func (s Stats) FreePercent() float64 {
	if s.TotalBytes == 0 {
		return 100
	}
	return 100 * float64(s.FreeBytes) / float64(s.TotalBytes)
}

// Root measures the filesystem backing path. Pass "/" for the root APFS
// container that holds ~/.tart on a Mac mini host. f_bavail (not f_bfree)
// is used so the figure matches `df` and excludes root-reserved blocks.
func Root(path string) (Stats, error) {
	var st unix.Statfs_t
	if err := unix.Statfs(path, &st); err != nil {
		return Stats{}, err
	}
	bsize := uint64(st.Bsize)
	return Stats{
		TotalBytes: st.Blocks * bsize,
		FreeBytes:  st.Bavail * bsize,
	}, nil
}
