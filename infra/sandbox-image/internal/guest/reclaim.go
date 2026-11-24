package guest

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Reclaimer returns an idle guest's page cache to the host. A Linux guest
// keeps file pages cached until it needs the memory, so its footprint on the
// host only grows. When the guest has a free-page-reporting balloon
// (sandboxd's BALLOON_FREE_PAGE_REPORTING), pages the kernel frees are
// handed back to the host, so after the guest has been idle for IdleTicks
// intervals the reclaimer asks the root cgroup's memory.reclaim to drop the
// cache above KeepBytes. Without the balloon freeing pages gains the host
// nothing, so it does not run.
type Reclaimer struct {
	Logger *slog.Logger
	// Root prefixes /proc and /sys; empty means "/".
	Root string
	// Interval between checks; IdleTicks consecutive idle intervals start a
	// reclaim, and the guest is idle while its CPU is busy less than
	// IdleShare of the interval.
	Interval  time.Duration
	IdleTicks int
	IdleShare float64
	// KeepBytes of page cache stay cached.
	KeepBytes uint64

	last      cpuTimes
	idleTicks int
}

// NewReclaimer is the guest's default: a check every 30 s, reclaiming after
// a minute under 5% busy and keeping 64 MiB of cache.
func NewReclaimer(logger *slog.Logger) *Reclaimer {
	return &Reclaimer{Logger: logger, Interval: 30 * time.Second, IdleTicks: 2, IdleShare: 0.05, KeepBytes: 64 << 20}
}

// Enabled reports whether the guest has a virtio balloon to return freed
// pages through.
func (r *Reclaimer) Enabled() bool {
	entries, err := os.ReadDir(r.path("sys/bus/virtio/drivers/virtio_balloon"))
	if err != nil {
		return false
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "virtio") {
			return true
		}
	}
	return false
}

// Run checks every Interval until ctx ends. It returns at once without a
// balloon.
func (r *Reclaimer) Run(ctx context.Context) {
	if !r.Enabled() {
		return
	}
	r.logger().Info("reclaiming idle page cache", slog.Duration("interval", r.Interval))
	ticker := time.NewTicker(r.Interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if _, err := r.Tick(); err != nil {
				r.logger().Warn("reclaim check failed", slog.Any("error", err))
			}
		}
	}
}

// Tick takes one reading and reclaims when the guest has been idle long
// enough. It returns the bytes it asked memory.reclaim for (0 when it did
// not reclaim).
func (r *Reclaimer) Tick() (uint64, error) {
	now, err := r.readCPU()
	if err != nil {
		return 0, err
	}
	prev := r.last
	r.last = now
	if prev.total == 0 || now.total <= prev.total {
		return 0, nil
	}
	busy := float64(now.busy-prev.busy) / float64(now.total-prev.total)
	if busy >= r.IdleShare {
		r.idleTicks = 0
		return 0, nil
	}
	r.idleTicks++
	if r.idleTicks < r.IdleTicks {
		return 0, nil
	}
	cached, err := r.cachedBytes()
	if err != nil || cached <= r.KeepBytes {
		return 0, err
	}
	want := cached - r.KeepBytes
	// The kernel answers EAGAIN when it reclaimed less than asked, which is
	// normal: some cache is dirty or mapped. Whatever it freed still counts.
	err = os.WriteFile(r.path("sys/fs/cgroup/memory.reclaim"), []byte(strconv.FormatUint(want, 10)), 0)
	if err != nil && !errors.Is(err, syscall.EAGAIN) {
		return 0, fmt.Errorf("memory.reclaim: %w", err)
	}
	after, _ := r.cachedBytes()
	r.logger().Info("reclaimed idle page cache", slog.Uint64("requested_bytes", want),
		slog.Uint64("cached_before_bytes", cached), slog.Uint64("cached_after_bytes", after))
	return want, nil
}

type cpuTimes struct{ busy, total uint64 }

// readCPU sums the aggregate cpu line of /proc/stat; idle and iowait count
// as not busy.
func (r *Reclaimer) readCPU() (cpuTimes, error) {
	f, err := os.Open(r.path("proc/stat"))
	if err != nil {
		return cpuTimes{}, err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	for s.Scan() {
		fields := strings.Fields(s.Text())
		if len(fields) < 6 || fields[0] != "cpu" {
			continue
		}
		var t cpuTimes
		for i, field := range fields[1:] {
			v, err := strconv.ParseUint(field, 10, 64)
			if err != nil {
				return cpuTimes{}, fmt.Errorf("/proc/stat: %w", err)
			}
			t.total += v
			if i != 3 && i != 4 { // idle, iowait
				t.busy += v
			}
		}
		return t, nil
	}
	return cpuTimes{}, errors.New("/proc/stat has no cpu line")
}

func (r *Reclaimer) cachedBytes() (uint64, error) {
	data, err := os.ReadFile(r.path("proc/meminfo"))
	if err != nil {
		return 0, err
	}
	for _, line := range strings.Split(string(data), "\n") {
		if rest, ok := strings.CutPrefix(line, "Cached:"); ok {
			kb, err := strconv.ParseUint(strings.TrimSuffix(strings.TrimSpace(rest), " kB"), 10, 64)
			if err != nil {
				return 0, fmt.Errorf("/proc/meminfo Cached: %w", err)
			}
			return kb << 10, nil
		}
	}
	return 0, errors.New("/proc/meminfo has no Cached line")
}

func (r *Reclaimer) path(rel string) string {
	root := r.Root
	if root == "" {
		root = "/"
	}
	return filepath.Join(root, rel)
}

func (r *Reclaimer) logger() *slog.Logger {
	if r.Logger != nil {
		return r.Logger
	}
	return slog.Default()
}
