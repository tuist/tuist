package reapi

import (
	"bufio"
	"errors"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
)

// Usage is what the action's command used while it ran, read from the cgroup
// it ran in: the server sizes the action's next run from it. Memory is the
// part the guest cannot reclaim (anonymous, shmem and kernel memory), so page
// cache, which fills any I/O-heavy VM, does not read as memory the action
// needs.
type Usage struct {
	CPUMs         int64   `json:"cpu_ms"`
	WallMs        int64   `json:"wall_ms"`
	P90Cores      float64 `json:"p90_cores"`
	AnonPeakBytes int64   `json:"anon_peak_bytes"`
	OOMKills      int64   `json:"oom_kills"`
	VCPUs         int     `json:"vcpus"`
}

// Meter measures one command. Prepare runs before the command starts and
// may place it in a cgroup, Start right after it started, and Stop once it
// exited; Stop returns what it used, and false when nothing was measured.
type Meter interface {
	Prepare(cmd *exec.Cmd) error
	Start()
	Stop() (Usage, bool)
}

// CgroupMeter runs the command in its own cgroup v2 under Root and samples it
// every Interval. The cgroup is root's, so the unprivileged command cannot
// leave it.
type CgroupMeter struct {
	Root     string
	Name     string
	Interval time.Duration
	// VCPUs the guest has; the per-second core readings are capped at it.
	VCPUs int

	dir      string
	fd       *os.File
	started  time.Time
	stop     chan struct{}
	done     chan struct{}
	mu       sync.Mutex
	samples  []float64
	lastCPU  int64
	lastAt   time.Time
	peak     int64
	prepared bool
}

// Prepare creates the cgroup, enables the cpu and memory controllers in its
// parent and starts the command directly in it (CLONE_INTO_CGROUP), so no
// process of the action runs outside it even briefly. A guest without cgroup
// v2 leaves the command where it is, unmeasured.
func (m *CgroupMeter) Prepare(cmd *exec.Cmd) error {
	if m.Interval <= 0 {
		m.Interval = time.Second
	}
	// The root can delegate controllers to its children: on cgroup v2 the
	// root cgroup is exempt from the no-internal-processes rule.
	_ = os.WriteFile(filepath.Join(m.Root, "cgroup.subtree_control"), []byte("+cpu +memory"), 0)
	m.dir = filepath.Join(m.Root, m.Name)
	if err := os.Mkdir(m.dir, 0o755); err != nil && !errors.Is(err, os.ErrExist) {
		return err
	}
	f, err := os.Open(m.dir)
	if err != nil {
		return err
	}
	if err := intoCgroup(cmd, f); err != nil {
		f.Close()
		return err
	}
	m.fd, m.prepared = f, true
	return nil
}

// Start begins sampling, once the command has started.
func (m *CgroupMeter) Start() {
	if m.fd != nil {
		m.fd.Close()
		m.fd = nil
	}
	if !m.prepared {
		return
	}
	m.started = time.Now()
	m.lastAt = m.started
	m.lastCPU, _ = m.cpuUsec()
	m.stop, m.done = make(chan struct{}), make(chan struct{})
	go func() {
		defer close(m.done)
		ticker := time.NewTicker(m.Interval)
		defer ticker.Stop()
		for {
			select {
			case <-m.stop:
				return
			case <-ticker.C:
				m.sample()
			}
		}
	}()
}

func (m *CgroupMeter) sample() {
	now := time.Now()
	cpu, ok := m.cpuUsec()
	memory, memoryOK := m.memoryBytes()
	m.mu.Lock()
	defer m.mu.Unlock()
	if ok {
		if elapsed := now.Sub(m.lastAt); elapsed > 0 {
			cores := float64(cpu-m.lastCPU) / float64(elapsed.Microseconds())
			if m.VCPUs > 0 {
				cores = math.Min(cores, float64(m.VCPUs))
			}
			m.samples = append(m.samples, math.Max(cores, 0))
		}
		m.lastCPU, m.lastAt = cpu, now
	}
	if memoryOK && memory > m.peak {
		m.peak = memory
	}
}

// Stop ends sampling and reads the totals.
func (m *CgroupMeter) Stop() (Usage, bool) {
	if !m.prepared || m.stop == nil {
		return Usage{}, false
	}
	close(m.stop)
	<-m.done
	m.sample()
	cpu, ok := m.cpuUsec()
	if !ok {
		return Usage{}, false
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	usage := Usage{CPUMs: cpu / 1000, WallMs: time.Since(m.started).Milliseconds(), AnonPeakBytes: m.peak, VCPUs: m.VCPUs}
	// memory.peak bounds a spike between two samples from above; it counts
	// page cache too, so it only replaces the sampled peak when that read
	// nothing.
	if usage.AnonPeakBytes == 0 {
		usage.AnonPeakBytes, _ = readInt(filepath.Join(m.dir, "memory.peak"))
	}
	usage.OOMKills, _ = m.keyed("memory.events", "oom_kill")
	if len(m.samples) > 0 {
		sorted := slices.Clone(m.samples)
		slices.Sort(sorted)
		usage.P90Cores = math.Round(sorted[min(len(sorted)-1, int(float64(len(sorted))*0.9))]*100) / 100
	}
	return usage, true
}

func (m *CgroupMeter) cpuUsec() (int64, bool) { return m.keyed("cpu.stat", "usage_usec") }

// memoryBytes is the cgroup's memory the guest cannot reclaim. Kernels from
// 6.1 report kernel memory as one field; older ones only its parts.
func (m *CgroupMeter) memoryBytes() (int64, bool) {
	stat, ok := m.stat("memory.stat")
	if !ok {
		return 0, false
	}
	total := stat["anon"] + stat["shmem"]
	if kernel, ok := stat["kernel"]; ok {
		total += kernel
	} else {
		total += stat["kernel_stack"] + stat["pagetables"] + stat["slab_unreclaimable"] + stat["percpu"] + stat["sock"]
	}
	return total, true
}

func (m *CgroupMeter) keyed(file, key string) (int64, bool) {
	stat, ok := m.stat(file)
	if !ok {
		return 0, false
	}
	v, ok := stat[key]
	return v, ok
}

func (m *CgroupMeter) stat(file string) (map[string]int64, bool) {
	f, err := os.Open(filepath.Join(m.dir, file))
	if err != nil {
		return nil, false
	}
	defer f.Close()
	out := map[string]int64{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) != 2 {
			continue
		}
		if v, err := strconv.ParseInt(fields[1], 10, 64); err == nil {
			out[fields[0]] = v
		}
	}
	return out, scanner.Err() == nil
}

func readInt(path string) (int64, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	v, err := strconv.ParseInt(strings.TrimSpace(string(b)), 10, 64)
	return v, err == nil
}

// UsageKind marks the command's usage in an action result's auxiliary
// metadata. The gateway reads it for the action's record and strips it, so it
// reaches neither the client nor the action cache.
const UsageKind = "tuist.usage"

func usageMetadata(u Usage) (*anypb.Any, error) {
	s, err := structpb.NewStruct(map[string]any{
		"kind": UsageKind, "cpu_ms": u.CPUMs, "wall_ms": u.WallMs, "p90_cores": u.P90Cores,
		"anon_peak_bytes": u.AnonPeakBytes, "oom_kills": u.OOMKills, "vcpus": u.VCPUs,
	})
	if err != nil {
		return nil, err
	}
	return anypb.New(s)
}

func isUsage(a *anypb.Any, s *structpb.Struct) bool {
	return a.MessageIs(s) && a.UnmarshalTo(s) == nil && s.Fields["kind"].GetStringValue() == UsageKind
}

// ReadUsage returns the usage the executor reported in md, if any.
func ReadUsage(md *re.ExecutedActionMetadata) (Usage, bool) {
	for _, a := range md.GetAuxiliaryMetadata() {
		var s structpb.Struct
		if !isUsage(a, &s) {
			continue
		}
		n := func(name string) float64 { return s.Fields[name].GetNumberValue() }
		return Usage{
			CPUMs: int64(n("cpu_ms")), WallMs: int64(n("wall_ms")), P90Cores: n("p90_cores"),
			AnonPeakBytes: int64(n("anon_peak_bytes")), OOMKills: int64(n("oom_kills")), VCPUs: int(n("vcpus")),
		}, true
	}
	return Usage{}, false
}

// StripUsage removes the usage from md.
func StripUsage(md *re.ExecutedActionMetadata) {
	if md == nil {
		return
	}
	md.AuxiliaryMetadata = slices.DeleteFunc(md.AuxiliaryMetadata, func(a *anypb.Any) bool { return isUsage(a, &structpb.Struct{}) })
}
