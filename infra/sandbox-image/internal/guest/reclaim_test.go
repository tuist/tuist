package guest

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

// A fake /proc and /sys: memory.reclaim is a plain file, so a write to it
// records what the reclaimer asked for.
func reclaimRoot(t *testing.T, balloon bool) string {
	t.Helper()
	root := t.TempDir()
	for _, d := range []string{"proc", "sys/fs/cgroup", "sys/bus/virtio/drivers/virtio_balloon"} {
		if err := os.MkdirAll(filepath.Join(root, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write(t, root, "sys/fs/cgroup/memory.reclaim", "")
	if balloon {
		if err := os.Mkdir(filepath.Join(root, "sys/bus/virtio/drivers/virtio_balloon/virtio2"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func write(t *testing.T, root, rel, data string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(root, rel), []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
}

// stat writes an aggregate cpu line whose busy and idle jiffies are given;
// iowait counts as idle.
func stat(t *testing.T, root string, busy, idle uint64) {
	write(t, root, "proc/stat", "cpu  "+strconv.FormatUint(busy, 10)+" 0 0 "+strconv.FormatUint(idle-10, 10)+" 10 0 0 0 0 0\ncpu0 1 2 3 4 5 6 7 8 9 10\n")
}

func TestReclaimerReclaimsOnlyAfterSustainedIdle(t *testing.T) {
	root := reclaimRoot(t, true)
	write(t, root, "proc/meminfo", "MemFree:  1000 kB\nCached:  2097152 kB\n")
	r := &Reclaimer{Root: root, IdleTicks: 2, IdleShare: 0.05, KeepBytes: 64 << 20}
	if !r.Enabled() {
		t.Fatal("balloon not detected")
	}
	ticks := []struct {
		busy, idle uint64
		want       uint64
	}{
		{1000, 1000, 0},              // first reading: nothing to compare against
		{1040, 2000, 0},              // 3.8% busy: idle, but only one tick
		{1200, 3000, 0},              // 13.8% busy: a build ran, idle count resets
		{1210, 4000, 0},              // idle once
		{1220, 5000, 2<<30 - 64<<20}, // idle twice: cache above 64 MiB
	}
	for i, tick := range ticks {
		stat(t, root, tick.busy, tick.idle)
		got, err := r.Tick()
		if err != nil {
			t.Fatal(err)
		}
		if got != tick.want {
			t.Fatalf("tick %d reclaimed %d, want %d", i, got, tick.want)
		}
	}
	data, _ := os.ReadFile(filepath.Join(root, "sys/fs/cgroup/memory.reclaim"))
	if string(data) != strconv.FormatUint(2<<30-64<<20, 10) {
		t.Fatalf("memory.reclaim = %q", data)
	}

	// Cache at or under the floor is left alone.
	write(t, root, "proc/meminfo", "Cached:    65536 kB\n")
	stat(t, root, 1230, 6000)
	if got, err := r.Tick(); err != nil || got != 0 {
		t.Fatalf("reclaimed %d under the floor: %v", got, err)
	}
}

func TestReclaimerNeedsABalloon(t *testing.T) {
	if (&Reclaimer{Root: reclaimRoot(t, false)}).Enabled() {
		t.Fatal("enabled without a balloon device")
	}
}
