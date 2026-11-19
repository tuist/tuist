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
// floor. Memory stays accounted, and limited, at the container's cgroup.
type VMCgroups struct {
	dir string
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
	return setupVMCgroups(cgroupRoot, ParseCgroupPath(string(data)), floorMilli)
}

func setupVMCgroups(root, base string, floorMilli uint64) (*VMCgroups, error) {
	dir := filepath.Join(root, base)
	controllers, err := os.ReadFile(filepath.Join(dir, "cgroup.controllers"))
	if err != nil {
		return nil, fmt.Errorf("reading the cgroup's controllers: %w", err)
	}
	if !slices.Contains(strings.Fields(string(controllers)), "cpu") {
		return nil, errors.New("the cpu controller is not available to the daemon's cgroup")
	}
	daemon := filepath.Join(dir, daemonCgroup)
	if err := os.Mkdir(daemon, 0o755); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, err
	}
	if err := moveProcesses(dir, daemon); err != nil {
		return nil, err
	}
	if err := os.WriteFile(filepath.Join(dir, "cgroup.subtree_control"), []byte("+cpu"), 0); err != nil {
		return nil, fmt.Errorf("enabling the cpu controller: %w", err)
	}
	if err := writeWeight(daemon, floorMilli); err != nil {
		return nil, err
	}
	// Nothing survives a Pod restart; a leftover leaf is empty.
	if entries, err := os.ReadDir(dir); err == nil {
		for _, entry := range entries {
			if entry.IsDir() && strings.HasPrefix(entry.Name(), vmCgroupPrefix) {
				_ = os.Remove(filepath.Join(dir, entry.Name()))
			}
		}
	}
	containerCgroup.Store(&base)
	return &VMCgroups{dir: dir}, nil
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

// Open creates (or reuses) the VM's cgroup, weighs it at guaranteeMilli
// and returns the directory for the VM's process to be spawned into
// (SysProcAttr.CgroupFD). The caller closes it once the process started.
func (c *VMCgroups) Open(id string, guaranteeMilli uint64) (*os.File, error) {
	dir := filepath.Join(c.dir, vmCgroupPrefix+id)
	if err := os.Mkdir(dir, 0o755); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, err
	}
	if err := writeWeight(dir, guaranteeMilli); err != nil {
		return nil, err
	}
	return os.Open(dir)
}

// Remove deletes the VM's cgroup once its process has exited; a cgroup
// left behind is reused by the VM's next start and removed at startup.
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
