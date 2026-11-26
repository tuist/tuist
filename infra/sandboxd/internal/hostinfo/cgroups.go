package hostinfo

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync/atomic"
)

const (
	// daemonCgroup is the leaf the daemon's own processes move into, so the
	// container's cgroup can delegate the cpu controller to its children:
	// cgroup v2 only enables a controller for children of a cgroup without
	// processes of its own. runc then joins `kubectl exec` processes to the
	// init process's cgroup, which is this leaf.
	daemonCgroup = "sandboxd"
	// vmCgroupPrefix names each VM's cgroup. It must never be the jailer's
	// default parent cgroup, "firecracker", which the jailer would move
	// itself into.
	vmCgroupPrefix = "vm-"
)

// containerCgroup is the container's own cgroup once SetupVMCgroups moved
// the daemon below it: the memory limit and usage the server places
// against are its, not the daemon's leaf's, which counts no guest.
var containerCgroup atomic.Pointer[string]

// VMCgroups gives every VM its own cgroup under the daemon container's,
// with a CPU weight proportional to its guaranteed CPU. The container's
// request, which the server raises to the sum of its sandboxes' guarantees,
// sets how much of the node's shared CPU the guests get when it is
// contended; the weights split that between the guests in proportion to
// their guarantees, and between them and the daemon in proportion to its
// floor. Memory stays limited at the container's cgroup; where the memory
// controller is available each VM's cgroup also accounts its own memory
// and protects its guest memory (memory.low) from the reclaim the
// container's limit drives, so the daemon's page cache goes first. It is
// memory.low and not memory.min: with the carve-out sized to reserved
// memory plus a little headroom, the kernel must still be able to drop a
// running guest's clean memory-file pages before it OOM-kills the
// container (memory.min made those unreclaimable and the daemons OOMed).
type VMCgroups struct {
	dir    string
	memory bool
}

// SetupVMCgroups moves the daemon's processes into a leaf of its
// container's cgroup, enables the cpu controller for the container's
// children and weighs the daemon's leaf at floorMilli. It needs cgroup v2
// with a writable hierarchy, which the privileged Pod has.
func SetupVMCgroups(floorMilli uint64) (*VMCgroups, error) {
	data, err := os.ReadFile(procSelfCgroup)
	if err != nil {
		return nil, err
	}
	return setupVMCgroups(cgroupRoot, ParseCgroupPath(string(data)), daemonCgroup, floorMilli)
}

// SetupVMMCgroups is SetupVMCgroups for the vmm container, which spawns the
// VMs for the daemon: its own process moves into a `vmm` leaf. It returns the
// container's cgroup, which the daemon adopts (AdoptVMCgroups).
func SetupVMMCgroups(floorMilli uint64) (string, error) {
	data, err := os.ReadFile(procSelfCgroup)
	if err != nil {
		return "", err
	}
	base := ParseCgroupPath(string(data))
	if _, err := setupVMCgroups(cgroupRoot, base, "vmm", floorMilli); err != nil {
		return "", err
	}
	return base, nil
}

// AdoptVMCgroups makes base, the vmm container's cgroup that
// SetupVMMCgroups prepared, where the daemon creates the VMs' cgroups and
// reads the memory limit the server resizes. It removes the leaves of VMs
// that no longer run, as SetupVMCgroups does at startup: a VM ends with the
// daemon's connection for it, so a restarted daemon finds them empty.
func AdoptVMCgroups(base string) (*VMCgroups, error) {
	return adoptVMCgroups(cgroupRoot, base)
}

// UseContainerCgroup reads memory from base without per-VM cgroups, for a
// vmm container that could not set them up: its cgroup still holds the VMs.
func UseContainerCgroup(base string) { containerCgroup.Store(&base) }

func adoptVMCgroups(root, base string) (*VMCgroups, error) {
	dir := filepath.Join(root, base)
	subtree, err := os.ReadFile(filepath.Join(dir, "cgroup.subtree_control"))
	if err != nil {
		return nil, fmt.Errorf("reading the vmm cgroup's controllers: %w", err)
	}
	// The kernel lists enabled controllers bare; tolerate the +cpu form
	// that was written.
	var enabled []string
	for _, field := range strings.Fields(string(subtree)) {
		enabled = append(enabled, strings.TrimPrefix(field, "+"))
	}
	if !slices.Contains(enabled, "cpu") {
		return nil, errors.New("the vmm cgroup does not delegate the cpu controller")
	}
	removeVMLeaves(dir)
	containerCgroup.Store(&base)
	return &VMCgroups{dir: dir, memory: slices.Contains(enabled, "memory")}, nil
}

// removeVMLeaves removes the VM leaves under dir; rmdir refuses a cgroup
// that still holds a process, so a running VM keeps its own.
func removeVMLeaves(dir string) {
	if entries, err := os.ReadDir(dir); err == nil {
		for _, entry := range entries {
			if entry.IsDir() && strings.HasPrefix(entry.Name(), vmCgroupPrefix) {
				_ = os.Remove(filepath.Join(dir, entry.Name()))
			}
		}
	}
}

func setupVMCgroups(root, base, leaf string, floorMilli uint64) (*VMCgroups, error) {
	dir := filepath.Join(root, base)
	controllers, err := os.ReadFile(filepath.Join(dir, "cgroup.controllers"))
	if err != nil {
		return nil, fmt.Errorf("reading the cgroup's controllers: %w", err)
	}
	if !slices.Contains(strings.Fields(string(controllers)), "cpu") {
		return nil, errors.New("the cpu controller is not available to the daemon's cgroup")
	}
	daemon := filepath.Join(dir, leaf)
	if err := os.Mkdir(daemon, 0o755); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, err
	}
	if err := moveProcesses(dir, daemon); err != nil {
		return nil, err
	}
	// Per-VM memory is best effort: without it VMs keep their CPU weights
	// and the server meters memory from their processes alone. The kernel
	// refuses the whole write when it cannot enable one controller.
	subtree := filepath.Join(dir, "cgroup.subtree_control")
	memory := slices.Contains(strings.Fields(string(controllers)), "memory") &&
		os.WriteFile(subtree, []byte("+cpu +memory"), 0) == nil
	if !memory {
		if err := os.WriteFile(subtree, []byte("+cpu"), 0); err != nil {
			return nil, fmt.Errorf("enabling the cpu controller: %w", err)
		}
	}
	if err := writeWeight(daemon, floorMilli); err != nil {
		return nil, err
	}
	// Nothing survives a Pod restart; a leftover leaf is empty.
	removeVMLeaves(dir)
	containerCgroup.Store(&base)
	return &VMCgroups{dir: dir, memory: memory}, nil
}

// moveProcesses moves every process of from into to. A process forked
// meanwhile lands in from and is moved by the next pass.
func moveProcesses(from, to string) error {
	for range 10 {
		data, err := os.ReadFile(filepath.Join(from, "cgroup.procs"))
		if err != nil {
			return err
		}
		pids := strings.Fields(string(data))
		if len(pids) == 0 {
			return nil
		}
		for _, pid := range pids {
			// A process that exited meanwhile fails with ESRCH and needs no move.
			_ = os.WriteFile(filepath.Join(to, "cgroup.procs"), []byte(pid), 0)
		}
	}
	return errors.New("processes kept appearing in the daemon's cgroup")
}

// Open creates (or reuses) the VM's cgroup, weighs it at guaranteeMilli,
// protects lowBytes of its memory and returns the directory for the VM's
// process to be spawned into (SysProcAttr.CgroupFD). The caller closes it
// once the process started.
func (c *VMCgroups) Open(id string, guaranteeMilli, lowBytes uint64) (*os.File, error) {
	dir := filepath.Join(c.dir, vmCgroupPrefix+id)
	if err := os.Mkdir(dir, 0o755); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, err
	}
	if err := writeWeight(dir, guaranteeMilli); err != nil {
		return nil, err
	}
	if c.memory {
		if err := os.WriteFile(filepath.Join(dir, "memory.low"), []byte(strconv.FormatUint(lowBytes, 10)), 0o644); err != nil {
			return nil, fmt.Errorf("protecting the memory of %s: %w", filepath.Base(dir), err)
		}
		// A reused cgroup must not keep a previous run's burst cap.
		if err := c.SetMemoryHigh(id, 0); err != nil {
			return nil, err
		}
	}
	return os.Open(dir)
}

// SetMemoryHigh caps the VM's cgroup at bytes (memory.high), zero for no
// cap. Above it the kernel reclaims the VM's page cache and throttles its
// faults instead of letting it fill the container, whose limit OOM-kills.
// A no-op without per-VM memory accounting.
func (c *VMCgroups) SetMemoryHigh(id string, bytes uint64) error {
	if c == nil || !c.memory {
		return nil
	}
	value := "max"
	if bytes > 0 {
		value = strconv.FormatUint(bytes, 10)
	}
	if err := os.WriteFile(filepath.Join(c.dir, vmCgroupPrefix+id, "memory.high"), []byte(value), 0o644); err != nil {
		return fmt.Errorf("capping the memory of %s: %w", vmCgroupPrefix+id, err)
	}
	return nil
}

// MemoryHeadroom is how much more the container's cgroup can hold before
// its limit OOM-kills: the limit less what it holds, counting its page
// cache (inactive and active file pages) as free, since the kernel drops
// that first. False without a container cgroup or a limit.
func MemoryHeadroom() (uint64, bool) {
	path, ok := ownCgroup()
	if !ok {
		return 0, false
	}
	return memoryHeadroom(cgroupRoot, path)
}

func memoryHeadroom(root, path string) (uint64, bool) {
	limit, ok := ReadCgroupValue(root, path, "memory.max", true)
	if !ok {
		return 0, false
	}
	current, ok := ReadCgroupValue(root, path, "memory.current", false)
	if !ok {
		return 0, false
	}
	var cache uint64
	if data, err := os.ReadFile(filepath.Join(root, path, "memory.stat")); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			key, value, _ := strings.Cut(line, " ")
			if key == "inactive_file" || key == "active_file" {
				n, _ := strconv.ParseUint(strings.TrimSpace(value), 10, 64)
				cache += n
			}
		}
	}
	held := current - min(cache, current)
	if held >= limit {
		return 0, true
	}
	return limit - held, true
}

// MemoryCurrent is everything charged to the VM's cgroup (memory.current):
// the guest memory its process touched plus the page cache its disk I/O
// filled. False without per-VM memory accounting or a readable cgroup.
func (c *VMCgroups) MemoryCurrent(id string) (uint64, bool) {
	if c == nil || !c.memory {
		return 0, false
	}
	data, err := os.ReadFile(filepath.Join(c.dir, vmCgroupPrefix+id, "memory.current"))
	if err != nil {
		return 0, false
	}
	bytes, err := strconv.ParseUint(strings.TrimSpace(string(data)), 10, 64)
	return bytes, err == nil
}

// Reweigh sets a running VM's cpu.weight to guaranteeMilli.
func (c *VMCgroups) Reweigh(id string, guaranteeMilli uint64) error {
	return writeWeight(filepath.Join(c.dir, vmCgroupPrefix+id), guaranteeMilli)
}

// Remove deletes the VM's cgroup once its process has exited (a pause, a
// death or a delete); the kernel moves the memory still charged to it to
// the container's cgroup. A cgroup left behind is reused by the VM's next
// start and removed at startup.
func (c *VMCgroups) Remove(id string) error {
	err := os.Remove(filepath.Join(c.dir, vmCgroupPrefix+id))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

// CPUWeight maps millicores to a cgroup v2 cpu.weight, which only counts
// relative to its siblings': a tenth of the millicores, so the default
// weight of 100 is one core, within the kernel's 1 to 10000.
func CPUWeight(milli uint64) uint64 {
	return min(max(milli/10, 1), 10000)
}

func writeWeight(dir string, milli uint64) error {
	if err := os.WriteFile(filepath.Join(dir, "cpu.weight"), []byte(strconv.FormatUint(CPUWeight(milli), 10)), 0o644); err != nil {
		return fmt.Errorf("setting the cpu weight of %s: %w", filepath.Base(dir), err)
	}
	return nil
}
