package podagent

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/hostdisk"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// customRootName holds the custom cache volumes, their journal and the checkout masters.
const customRootName = "custom"

// volumeBackend is the filesystem probes the cache space needs; tests inject a fake.
type volumeBackend interface {
	freeBytes(root string) (uint64, error)
	// capacityBytes is the runner-cache volume's quota.
	capacityBytes(root string) (uint64, error)
	// usedBytes is the APFS volume's own usage, not its container's.
	usedBytes(root string) (uint64, error)
	allocatedBytes(path string) (uint64, error)
	// isMounted tells a mounted volume from a bare mountpoint on the boot disk, which df cannot.
	isMounted(root string) (bool, error)
}

// CacheSpace is the quota-bounded APFS volume every runner cache on the host shares.
type CacheSpace struct {
	// Root is the runner-cache volume's mount point; empty disables runner caches.
	Root string

	// BudgetGiB, when > 0, is what every cache on the volume may take together, below its quota.
	BudgetGiB int

	HostDiskSpace func() (hostdisk.Stats, error)

	// Running reports whether a Tart VM is running; the leftover sweep keeps a running VM's share.
	Running func(ctx context.Context, vm string) (bool, error)

	backend volumeBackend

	// mu serializes admission: reservations are recorded under it, never downloads or image creation.
	mu sync.Mutex

	ReconcileInterval time.Duration

	mountCheckInterval time.Duration
	mountCheckAttempts int
}

// NewCacheSpace returns a disabled space for an empty root, and the platform backend for a nil one.
func NewCacheSpace(root string, backend volumeBackend) *CacheSpace {
	var hostSpace func() (hostdisk.Stats, error)
	if backend == nil {
		backend = newVolumeBackend()
		hostSpace = func() (hostdisk.Stats, error) { return hostdisk.Root("/") }
	}
	return &CacheSpace{Root: root, backend: backend, HostDiskSpace: hostSpace}
}

func (m *CacheSpace) Enabled() bool { return m != nil && m.Root != "" }

// Start publishes the mount and free-space gauges and sweeps leftovers on every tick.
func (m *CacheSpace) Start(ctx context.Context) error {
	if !m.Enabled() {
		return nil
	}
	RecordVolumeEnabled()
	logger := log.FromContext(ctx).WithName("cache-volumes")
	interval := m.ReconcileInterval
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	tick := func() {
		mounted, err := m.backend.isMounted(m.Root)
		if err != nil {
			logger.Error(err, "check runner-cache root mount state", "root", m.Root)
		}
		RecordVolumeRootMounted(mounted)
		if !mounted {
			return
		}
		m.sweepLeftovers(ctx)
		if free, err := m.volumeFreeBytes(); err == nil {
			RecordVolumeRootFree(free)
		}
	}
	tick()
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			tick()
		}
	}
}

// sweepLeftovers removes the built-in cache's per-account masters, VM branches, download staging and report queue.
func (m *CacheSpace) sweepLeftovers(ctx context.Context) {
	entries, err := os.ReadDir(m.Root)
	if err != nil {
		return
	}
	logger := log.FromContext(ctx).WithName("cache-volumes")
	before, usedErr := m.backend.usedBytes(m.Root)
	var removed []string
	for _, entry := range entries {
		name := entry.Name()
		if !entry.IsDir() || (name != "branches" && name != "_converge" && name != "usage-reports" && !isAccountID(name)) {
			if name != customRootName && !strings.HasPrefix(name, ".") {
				logger.V(1).Info("left an unknown entry on the runner-cache root", "name", name)
			}
			continue
		}
		path := filepath.Join(m.Root, name)
		if name == "branches" {
			removed = append(removed, m.sweepBranches(ctx, path)...)
			continue
		}
		if err := os.RemoveAll(path); err != nil {
			logger.Error(err, "remove leftover from the runner-cache root", "path", path)
			continue
		}
		removed = append(removed, name)
	}
	if len(removed) == 0 {
		return
	}
	fields := []any{"root", m.Root, "removed", removed}
	if after, err := m.backend.usedBytes(m.Root); usedErr == nil && err == nil {
		fields = append(fields, "freed_bytes", saturatingSub(before, after))
	}
	logger.Info("removed leftovers from the runner-cache root", fields...)
}

func isAccountID(name string) bool {
	if name == "" || len(name) > 19 {
		return false
	}
	for _, r := range name {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func (m *CacheSpace) sweepBranches(ctx context.Context, dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var removed []string
	kept := 0
	for _, entry := range entries {
		if m.vmRunning(ctx, entry.Name()) {
			kept++
			continue
		}
		if err := os.RemoveAll(filepath.Join(dir, entry.Name())); err != nil {
			kept++
			continue
		}
		removed = append(removed, filepath.Join("branches", entry.Name()))
	}
	if kept == 0 && os.Remove(dir) == nil {
		removed = append(removed, "branches")
	}
	return removed
}

func (m *CacheSpace) vmRunning(ctx context.Context, vm string) bool {
	if m.Running == nil {
		return true
	}
	running, err := m.Running(ctx, vm)
	return err != nil || running
}

// AwaitMountedRoot waits, bounded, for the root to mount so the first Pods after a reboot get their share.
func (m *CacheSpace) AwaitMountedRoot(ctx context.Context) {
	if !m.Enabled() {
		return
	}
	RecordVolumeEnabled()
	logger := log.Log.WithName("cache-volumes")
	interval := m.mountCheckInterval
	if interval <= 0 {
		interval = 10 * time.Second
	}
	attempts := m.mountCheckAttempts
	if attempts <= 0 {
		attempts = 12
	}
	for attempt := 1; ; attempt++ {
		mounted, err := m.backend.isMounted(m.Root)
		RecordVolumeRootMounted(mounted)
		if mounted && err == nil {
			if attempt > 1 {
				logger.Info("runner-cache root is now mounted", "root", m.Root, "attempt", attempt)
			}
			return
		}
		if attempt >= attempts {
			logger.Error(err, "runner-cache root is still not a mounted volume after all attempts; jobs on this host run without cache volumes until it is mounted or the host is re-provisioned",
				"root", m.Root, "attempts", attempts)
			return
		}
		logger.Error(err, "runner-cache root is set but not a mounted volume; retrying",
			"root", m.Root, "attempt", attempt, "max_attempts", attempts, "retry_in", interval.String())
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}

func saturatingSub(a, b uint64) uint64 {
	if b >= a {
		return 0
	}
	return a - b
}
