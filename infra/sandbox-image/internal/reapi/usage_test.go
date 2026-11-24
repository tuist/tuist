package reapi

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
)

func writeStat(t *testing.T, dir, file, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, file), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// The meter is driven by hand against a fake cgroup directory: page cache
// ("file") never counts as memory, the peak survives a later drop, and
// p90 cores come from the per-interval CPU deltas.
func TestCgroupMeterReadsUnreclaimableMemoryAndCores(t *testing.T) {
	dir := t.TempDir()
	m := &CgroupMeter{dir: dir, prepared: true, VCPUs: 8, Interval: time.Hour}
	writeStat(t, dir, "cpu.stat", "usage_usec 0\nuser_usec 0\n")
	writeStat(t, dir, "memory.stat", "anon 100\nfile 900000\nshmem 10\nkernel 5\n")
	m.Start()

	// About 4 cores busy over the first sample.
	m.lastAt = time.Now().Add(-time.Second)
	writeStat(t, dir, "cpu.stat", "usage_usec 4000000\n")
	writeStat(t, dir, "memory.stat", "anon 3000\nfile 5\nshmem 20\nkernel 7\n")
	m.sample()

	writeStat(t, dir, "memory.stat", "anon 50\nfile 1\nshmem 0\nkernel 1\n")
	writeStat(t, dir, "memory.events", "low 0\noom 1\noom_kill 2\n")
	usage, ok := m.Stop()
	if !ok {
		t.Fatal("no usage")
	}
	if usage.AnonPeakBytes != 3027 {
		t.Errorf("peak = %d, want 3027 (anon+shmem+kernel, no page cache)", usage.AnonPeakBytes)
	}
	if usage.CPUMs != 4000 || usage.OOMKills != 2 || usage.VCPUs != 8 {
		t.Errorf("usage = %+v", usage)
	}
	if usage.P90Cores < 3.5 || usage.P90Cores > 4.01 {
		t.Errorf("p90 cores = %v, want about 4", usage.P90Cores)
	}
}

func TestCgroupMeterSumsKernelPartsOnOlderKernels(t *testing.T) {
	dir := t.TempDir()
	m := &CgroupMeter{dir: dir}
	writeStat(t, dir, "memory.stat", "anon 1\nshmem 2\nkernel_stack 4\npagetables 8\nslab_unreclaimable 16\nslab_reclaimable 1000\npercpu 32\nsock 64\n")
	if got, _ := m.memoryBytes(); got != 127 {
		t.Errorf("memory = %d, want 127", got)
	}
}

func TestUsageRoundTripsThroughAuxiliaryMetadataAndStrips(t *testing.T) {
	want := Usage{CPUMs: 12345, WallMs: 6789, P90Cores: 3.5, AnonPeakBytes: 3 << 30, OOMKills: 1, VCPUs: 8}
	a, err := usageMetadata(want)
	if err != nil {
		t.Fatal(err)
	}
	cas, _ := structpb.NewStruct(map[string]any{"kind": "tuist.cas_reads"})
	other, _ := anypb.New(cas)
	md := &re.ExecutedActionMetadata{AuxiliaryMetadata: []*anypb.Any{other, a}}
	got, ok := ReadUsage(md)
	if !ok || got != want {
		t.Fatalf("ReadUsage = %+v, %v; want %+v", got, ok, want)
	}
	StripUsage(md)
	if len(md.AuxiliaryMetadata) != 1 || md.AuxiliaryMetadata[0] != other {
		t.Errorf("strip left %v", md.AuxiliaryMetadata)
	}
}
