package sensors

import (
	"strings"
	"testing"
)

func TestAccountDiskIOCountsEachProcessOnceAcrossSamples(t *testing.T) {
	vm := "com.apple.Virtualization.VirtualMachine"
	// The first sample only seeds: the kubelet's lifetime bytes are not a
	// burst.
	s := accountDiskIO(nil, []ProcessIO{
		{PID: 100, Start: 1, Name: "tart-kubelet", Written: 900e9},
		{PID: 200, Start: 5, Name: vm, Written: 10e9},
	})
	if got := s.Totals["tart-kubelet"].Written; got != 0 {
		t.Fatalf("first sample counted %d kubelet bytes, want 0", got)
	}

	s = accountDiskIO(&s, []ProcessIO{
		{PID: 100, Start: 1, Name: "tart-kubelet", Written: 900e9 + 3e9},
		// The VM exited, and a new process reused its PID: its bytes all
		// count, not the difference from the old VM's.
		{PID: 200, Start: 9, Name: vm, Written: 4e9, Read: 1e9},
		// A process that started since the last sample counts from zero.
		{PID: 300, Start: 8, Name: "diskimages-helper", Written: 2e9},
		{PID: 400, Start: 8, Name: "mds_stores", Written: 5e6},
	})
	want := map[string]DiskIO{
		"tart-kubelet": {Written: 3e9},
		"vm":           {Written: 4e9, Read: 1e9},
		"disk-images":  {Written: 2e9},
		"other":        {Written: 5e6},
	}
	for g, w := range want {
		if got := s.Totals[g]; got != w {
			t.Errorf("%s = %+v, want %+v", g, got, w)
		}
	}

	// The VM is gone: the totals keep what it wrote, so they stay counters.
	s = accountDiskIO(&s, []ProcessIO{{PID: 100, Start: 1, Name: "tart-kubelet", Written: 900e9 + 4e9}})
	if got := s.Totals["vm"].Written; got != 4e9 {
		t.Errorf("vm after exit = %d, want 4e9", got)
	}
	if got := s.Totals["tart-kubelet"].Written; got != 4e9 {
		t.Errorf("tart-kubelet = %d, want 4e9", got)
	}
	if _, ok := s.Processes["200@9"]; ok {
		t.Errorf("exited process still tracked")
	}
}

func TestFormatRendersEveryDiskIOGroupAsACounter(t *testing.T) {
	got := Format(Readings{DiskIO: map[string]DiskIO{"vm": {Read: 7, Written: 42}}})
	for _, line := range []string{
		"# TYPE macos_process_disk_written_bytes_total counter",
		`macos_process_disk_written_bytes_total{group="vm"} 42`,
		`macos_process_disk_read_bytes_total{group="vm"} 7`,
		`macos_process_disk_written_bytes_total{group="tart-kubelet"} 0`,
		`macos_process_disk_written_bytes_total{group="other"} 0`,
	} {
		if !strings.Contains(got, line+"\n") {
			t.Errorf("missing %q in:\n%s", line, got)
		}
	}
}
