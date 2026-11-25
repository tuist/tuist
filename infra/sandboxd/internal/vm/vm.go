// Package vm spawns and tracks one Firecracker process per sandbox, under
// the jailer by default. The jail root <base>/firecracker/<id>/root is the
// chroot, so in-jail paths (/vmlinux, /rootfs.ext4, /mem, ...) are what the
// API sees while the daemon reads and writes the same files at Root()+path.
package vm

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/safepath"
)

const (
	LogFileName = "firecracker.log"
	// MaxLogBytes caps firecracker.log, which also receives the guest's
	// serial console: past it the file starts over, so a guest writing to
	// ttyS0 cannot fill the node's disk.
	MaxLogBytes = 8 << 20
	pidFileName = "firecracker.pid"
	// DefaultNetNSDir is where `ip netns add` mounts namespaces.
	DefaultNetNSDir = "/var/run/netns"
)

// idPattern is the jailer's constraint on --id.
var idPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9-]{0,63}$`)

func ValidateID(id string) error {
	if _, err := safepath.Segment(id); err != nil {
		return fmt.Errorf("invalid id: %w", err)
	}
	if !idPattern.MatchString(id) {
		return fmt.Errorf("invalid id %q: must match %s", id, idPattern)
	}
	return nil
}

// Spec describes one Firecracker process.
type Spec struct {
	ID             string
	JailBase       string
	FirecrackerBin string
	JailerBin      string
	JailerEnabled  bool
	UID            int
	GID            int
	NetNS          string
	NetNSDir       string
	// Cgroup, when set, is the cgroup v2 directory the process is spawned
	// into (clone3 CLONE_INTO_CGROUP), so Firecracker and its vCPU threads
	// run there from their first instruction. The jailer moves nothing
	// without --cgroup arguments.
	Cgroup *os.File `json:"-"`
	// MountNS, when set, is the mount namespace the process starts in
	// (nsenter --mount): the daemon's, when the vmm container spawns it, so
	// the jailer sees the network namespaces and lazy-disk mounts the daemon
	// made in its own namespace.
	MountNS *os.File `json:"-"`
}

// NsenterBin runs a spawn inside Spec.MountNS.
var NsenterBin = "nsenter"

// Instance is a spawned Firecracker process.
type Instance interface {
	ID() string
	Root() string
	HostPath(inJail string) string
	GuestPath(inJail string) string
	API() *firecracker.Client
	VsockPath() string
	PID() int
	// CPUTime is the guest's CPU time: the user and system time of the
	// VM's vCPU threads, without the VMM's own device emulation; false
	// where it cannot be read.
	CPUTime() (time.Duration, bool)
	// ResidentMemory is what the VMM process holds resident; false where it cannot
	// be read.
	ResidentMemory() (Memory, bool)
	Done() <-chan struct{}
	ExitError() error
	Kill(ctx context.Context) error
}

type Launcher interface {
	Launch(ctx context.Context, spec Spec) (Instance, error)
}

// RootDir is the jail root the jailer builds for an id. Ids are validated
// before they get here; an id that would still escape the base maps to a
// quarantine directory inside it rather than anywhere else on the node.
func RootDir(base, id string) string {
	return jailPath(base, id, "root")
}

// JailDir is the per-id directory above the root (holds the pid file and
// the exec copy).
func JailDir(base, id string) string {
	return jailPath(base, id)
}

func jailPath(base, id string, more ...string) string {
	if _, err := safepath.Segment(id); err != nil {
		id = "invalid"
	}
	p, err := safepath.Under(base, append([]string{"firecracker", id}, more...)...)
	if err != nil {
		p, _ = safepath.Under(base, append([]string{"firecracker", "invalid"}, more...)...)
	}
	return p
}

// Prepare creates the jail root for a spawn and removes what a previous
// Firecracker left behind: the API and vsock sockets (Firecracker will not
// bind over an existing file), the pid file the jailer creates with O_EXCL,
// and the whole /dev tree, because the jailer mknods kvm, net/tun, urandom
// and userfaultfd itself and fails on EEXIST.
func Prepare(root string, uid, gid int) error {
	for _, dir := range []string{root, filepath.Join(root, "run")} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		if err := Chown(dir, uid, gid); err != nil {
			return err
		}
	}
	for _, stale := range []string{
		filepath.Join(root, firecracker.APISocketPath),
		filepath.Join(root, firecracker.VsockPath),
		filepath.Join(root, pidFileName),
	} {
		if err := os.Remove(stale); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("removing %s: %w", stale, err)
		}
	}
	if err := os.RemoveAll(filepath.Join(root, "dev")); err != nil {
		return fmt.Errorf("removing stale /dev: %w", err)
	}
	return nil
}

// Command builds the binary and arguments for a spec. Exported for tests.
func Command(spec Spec) (string, []string) {
	root := RootDir(spec.JailBase, spec.ID)
	nsDir := spec.NetNSDir
	if nsDir == "" {
		nsDir = DefaultNetNSDir
	}
	if spec.JailerEnabled {
		args := []string{
			"--id", spec.ID,
			"--exec-file", spec.FirecrackerBin,
			"--uid", strconv.Itoa(spec.UID),
			"--gid", strconv.Itoa(spec.GID),
			"--chroot-base-dir", spec.JailBase,
		}
		if spec.NetNS != "" {
			args = append(args, "--netns", filepath.Join(nsDir, spec.NetNS))
		}
		args = append(args, "--new-pid-ns", "--cgroup-version", "2", "--", "--api-sock", firecracker.APISocketPath)
		return spec.JailerBin, args
	}
	direct := []string{"--id", spec.ID, "--api-sock", filepath.Join(root, firecracker.APISocketPath)}
	if spec.NetNS != "" {
		return "ip", append([]string{"netns", "exec", spec.NetNS, spec.FirecrackerBin}, direct...)
	}
	return spec.FirecrackerBin, direct
}

// FirecrackerLauncher spawns real Firecracker processes.
type FirecrackerLauncher struct {
	Log        *slog.Logger
	APITimeout time.Duration
}

type machine struct {
	spec   Spec
	root   string
	client *firecracker.Client
	log    *slog.Logger

	cmd     *exec.Cmd
	logFile *cappedLog
	pid     atomic.Int64
	killed  atomic.Bool
	done    chan struct{}
	exitMu  sync.Mutex
	exitErr error
}

func (l *FirecrackerLauncher) Launch(ctx context.Context, spec Spec) (Instance, error) {
	if err := ValidateID(spec.ID); err != nil {
		return nil, err
	}
	logger := l.Log
	if logger == nil {
		logger = slog.Default()
	}
	root := RootDir(spec.JailBase, spec.ID)
	if err := Prepare(root, spec.UID, spec.GID); err != nil {
		return nil, fmt.Errorf("preparing jail %s: %w", root, err)
	}
	// The jailer copies Firecracker into the jail root and fails with
	// ETXTBSY when a killed predecessor's image is still mapped, as after a
	// warm restore whose userfaultfd server still held its memory. Unlinking
	// the copy lets the jailer write a new one either way.
	if spec.JailerEnabled {
		jailed := filepath.Join(root, filepath.Base(spec.FirecrackerBin))
		if err := os.Remove(jailed); err != nil && !errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("removing %s: %w", jailed, err)
		}
	}
	logFile, err := openCappedLog(filepath.Join(root, LogFileName), MaxLogBytes)
	if err != nil {
		return nil, err
	}
	// Firecracker gets the write end of a pipe rather than the file, so the
	// daemon decides how much of its output (and the guest console) reaches
	// the disk. An *os.File keeps exec.Cmd from adding its own copy
	// goroutine, which would hold Wait open until Firecracker exits and hide
	// the jailer's own early exit.
	pipeR, pipeW, err := os.Pipe()
	if err != nil {
		logFile.Close()
		return nil, err
	}
	bin, args := Command(spec)
	if spec.MountNS != nil {
		// ExtraFiles start at fd 3. nsenter execs in place, so the process
		// group below is still the jailer's.
		args = append([]string{"--mount=/proc/self/fd/3", "--wd=" + root, "--", bin}, args...)
		bin = NsenterBin
	}
	cmd := exec.Command(bin, args...)
	cmd.Dir = root
	if spec.MountNS != nil {
		cmd.ExtraFiles = []*os.File{spec.MountNS}
	}
	cmd.Stdout = pipeW
	cmd.Stderr = pipeW
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if spec.Cgroup != nil {
		cmd.SysProcAttr.UseCgroupFD = true
		cmd.SysProcAttr.CgroupFD = int(spec.Cgroup.Fd())
	}
	fmt.Fprintf(logFile, "\n==== %s sandboxd spawn: %s %s\n", time.Now().UTC().Format(time.RFC3339), bin, strings.Join(args, " "))
	if err := cmd.Start(); err != nil {
		pipeW.Close()
		pipeR.Close()
		logFile.Close()
		return nil, fmt.Errorf("starting %s: %w", bin, err)
	}
	pipeW.Close()
	go func() {
		defer pipeR.Close()
		_, _ = io.Copy(logFile, pipeR)
	}()
	m := &machine{
		spec:    spec,
		root:    root,
		client:  firecracker.NewClient(filepath.Join(root, firecracker.APISocketPath)),
		log:     logger.With("vm", spec.ID),
		cmd:     cmd,
		logFile: logFile,
		done:    make(chan struct{}),
	}
	m.pid.Store(int64(cmd.Process.Pid))

	parentExited := make(chan error, 1)
	go func() { parentExited <- cmd.Wait() }()

	timeout := l.APITimeout
	if timeout == 0 {
		timeout = 10 * time.Second
	}
	if spec.JailerEnabled {
		// The jailer parent exits as soon as it has forked Firecracker into
		// the new pid namespace; a non-zero status here means it never got
		// that far.
		select {
		case err := <-parentExited:
			if err != nil {
				m.log.Warn("jailer failed", "error", err, "log", m.LogTail(2048))
				m.finish(fmt.Errorf("jailer: %w", err))
				return nil, m.ExitError()
			}
		case <-time.After(timeout):
			m.log.Warn("jailer parent still running; continuing")
		case <-ctx.Done():
			m.abort(ctx.Err())
			return nil, ctx.Err()
		}
		pid, err := readPIDFile(filepath.Join(root, pidFileName))
		if err != nil {
			m.log.Warn("reading firecracker pid failed", "error", err, "log", m.LogTail(2048))
			m.abort(err)
			return nil, fmt.Errorf("reading firecracker pid: %w", err)
		}
		m.pid.Store(int64(pid))
		go func() {
			m.finish(waitExit(pid))
		}()
	} else {
		go func() {
			err := <-parentExited
			m.finish(err)
		}()
	}

	if err := m.client.WaitReady(ctx, timeout); err != nil {
		select {
		case <-m.done:
			m.log.Warn("firecracker exited before its API came up", "error", m.ExitError(), "log", m.LogTail(2048))
			return nil, fmt.Errorf("firecracker exited before its API came up: %w", m.ExitError())
		default:
		}
		_ = m.Kill(context.Background())
		return nil, err
	}
	return m, nil
}

func readPIDFile(path string) (int, error) {
	deadline := time.Now().Add(5 * time.Second)
	for {
		data, err := os.ReadFile(path)
		if err == nil {
			pid, convErr := strconv.Atoi(strings.TrimSpace(string(data)))
			if convErr == nil && pid > 0 {
				return pid, nil
			}
			err = fmt.Errorf("malformed pid file %q", strings.TrimSpace(string(data)))
		}
		if time.Now().After(deadline) {
			return 0, err
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func (m *machine) finish(err error) {
	m.exitMu.Lock()
	defer m.exitMu.Unlock()
	select {
	case <-m.done:
		return
	default:
	}
	if m.killed.Load() && err != nil {
		err = fmt.Errorf("killed by sandboxd (%v)", err)
	}
	m.exitErr = err
	if m.logFile != nil {
		fmt.Fprintf(m.logFile, "==== %s sandboxd: process ended: %v\n", time.Now().UTC().Format(time.RFC3339), err)
		m.logFile.Close()
	}
	close(m.done)
}

func (m *machine) ID() string                    { return m.spec.ID }
func (m *machine) Root() string                  { return m.root }
func (m *machine) HostPath(inJail string) string { return filepath.Join(m.root, inJail) }
func (m *machine) API() *firecracker.Client      { return m.client }
func (m *machine) VsockPath() string             { return m.HostPath(firecracker.VsockPath) }
func (m *machine) PID() int                      { return int(m.pid.Load()) }
func (m *machine) Done() <-chan struct{}         { return m.done }
func (m *machine) Killed() bool                  { return m.killed.Load() }

// GuestPath is the path the Firecracker API should see: unchanged under the
// jailer (chroot), absolute host path without it.
func (m *machine) GuestPath(inJail string) string {
	if m.spec.JailerEnabled {
		return inJail
	}
	return m.HostPath(inJail)
}

func (m *machine) ExitError() error {
	m.exitMu.Lock()
	defer m.exitMu.Unlock()
	return m.exitErr
}

// abort kills a launch that failed before anything watches the process:
// Kill would wait for an exit nobody reports, so the exit is recorded here.
func (m *machine) abort(err error) {
	m.killed.Store(true)
	_ = syscall.Kill(-m.cmd.Process.Pid, syscall.SIGKILL)
	if pid := m.PID(); pid > 0 && pid != m.cmd.Process.Pid {
		_ = syscall.Kill(pid, syscall.SIGKILL)
	}
	m.finish(err)
}

// Kill sends SIGKILL to the process group and the tracked pid and waits for
// the exit to be observed.
func (m *machine) Kill(ctx context.Context) error {
	m.killed.Store(true)
	select {
	case <-m.done:
		return nil
	default:
	}
	pgid := m.cmd.Process.Pid
	_ = syscall.Kill(-pgid, syscall.SIGKILL)
	if pid := m.PID(); pid > 0 && pid != pgid {
		_ = syscall.Kill(pid, syscall.SIGKILL)
	}
	select {
	case <-m.done:
		return nil
	case <-ctx.Done():
		return fmt.Errorf("waiting for firecracker %d to die: %w", m.PID(), ctx.Err())
	}
}

// LogTail returns the last n bytes of firecracker.log for error messages.
func (m *machine) LogTail(n int64) string {
	return LogTail(filepath.Join(m.root, LogFileName), n)
}

func LogTail(path string, n int64) string {
	f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return ""
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return ""
	}
	if info.Size() > n {
		if _, err := f.Seek(-n, io.SeekEnd); err != nil {
			return ""
		}
	}
	data, _ := io.ReadAll(f)
	return strings.TrimSpace(string(data))
}

// cappedLog appends to a file the jailed Firecracker could tamper with, so
// it never follows a symlink, and starts the file over once it exceeds max
// bytes.
type cappedLog struct {
	mu     sync.Mutex
	file   *os.File
	size   int64
	max    int64
	closed bool
}

func openCappedLog(path string, max int64) (*cappedLog, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|syscall.O_NOFOLLOW, 0o644)
	if err != nil {
		return nil, err
	}
	info, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, err
	}
	l := &cappedLog{file: file, max: max, size: info.Size()}
	if l.size > max {
		if err := l.restart(); err != nil {
			file.Close()
			return nil, err
		}
	} else if _, err := file.Seek(0, io.SeekEnd); err != nil {
		file.Close()
		return nil, err
	}
	return l, nil
}

func (l *cappedLog) restart() error {
	if err := l.file.Truncate(0); err != nil {
		return err
	}
	if _, err := l.file.Seek(0, io.SeekStart); err != nil {
		return err
	}
	l.size = 0
	n, err := fmt.Fprintf(l.file, "==== %s sandboxd: log exceeded %d bytes and was truncated\n", time.Now().UTC().Format(time.RFC3339), l.max)
	l.size += int64(n)
	return err
}

// Write never fails towards the copier: dropping console output is better
// than blocking Firecracker on a full pipe.
func (l *cappedLog) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed {
		return len(p), nil
	}
	if l.size+int64(len(p)) > l.max {
		if err := l.restart(); err != nil {
			return len(p), nil
		}
		if int64(len(p)) > l.max/2 {
			p = p[int64(len(p))-l.max/2:]
		}
	}
	n, _ := l.file.Write(p)
	l.size += int64(n)
	return len(p), nil
}

func (l *cappedLog) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed {
		return nil
	}
	l.closed = true
	return l.file.Close()
}

func (m *machine) CPUTime() (time.Duration, bool) { return vcpuCPUTime("/proc", m.PID()) }

// userHZ is the unit of utime and stime in /proc/<pid>/stat.
const userHZ = 100

// vcpuThreadPrefix names Firecracker's vCPU threads (`fc_vcpu <index>`).
// Its other threads (the VMM's event loop, which emulates the virtio
// devices, and the API server) do the host's work for the guest, which
// the guest cannot see and is not billed for.
const vcpuThreadPrefix = "fc_vcpu"

// vcpuCPUTime sums the CPU time of the process's vCPU threads. A process
// without any, such as a VMM that names its threads otherwise, counts as
// a whole.
func vcpuCPUTime(proc string, pid int) (time.Duration, bool) {
	if pid <= 0 {
		return 0, false
	}
	process := filepath.Join(proc, strconv.Itoa(pid))
	tasks, err := os.ReadDir(filepath.Join(process, "task"))
	if err != nil {
		return 0, false
	}
	var total time.Duration
	vcpus := 0
	for _, task := range tasks {
		comm, err := os.ReadFile(filepath.Join(process, "task", task.Name(), "comm"))
		if err != nil || !strings.HasPrefix(string(comm), vcpuThreadPrefix) {
			continue
		}
		data, err := os.ReadFile(filepath.Join(process, "task", task.Name(), "stat"))
		if err != nil {
			continue
		}
		if cpu, ok := parseStatCPUTime(string(data)); ok {
			total += cpu
			vcpus++
		}
	}
	if vcpus > 0 {
		return total, true
	}
	data, err := os.ReadFile(filepath.Join(process, "stat"))
	if err != nil {
		return 0, false
	}
	return parseStatCPUTime(string(data))
}

// Memory is a VMM process's resident memory, proportional to sharing
// (/proc/<pid>/smaps_rollup's Pss fields), so summing it over every VM on a
// node does not count a page twice. Guest memory restored from a memory
// file (the File backend maps it private) is file-backed until the guest
// writes it: clean file pages, such as the shared template memfile, are host
// page cache the kernel can drop and read back, while anonymous pages are
// what the guest wrote and the host can only keep (no swap).
type Memory struct {
	AnonBytes uint64
	FileBytes uint64
}

func (m *machine) ResidentMemory() (Memory, bool) { return processMemory(m.PID()) }

func processMemory(pid int) (Memory, bool) {
	if pid <= 0 {
		return Memory{}, false
	}
	data, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/smaps_rollup")
	if err != nil {
		return Memory{}, false
	}
	return parseSmapsRollup(string(data))
}

// parseSmapsRollup reads Pss_Anon, Pss_File and Pss_Shmem (kB). Shmem
// counts as file: it is what a memfd backend would show.
func parseSmapsRollup(text string) (Memory, bool) {
	var mem Memory
	found := false
	for _, line := range strings.Split(text, "\n") {
		key, rest, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		fields := strings.Fields(rest)
		if len(fields) == 0 {
			continue
		}
		kb, err := strconv.ParseUint(fields[0], 10, 64)
		if err != nil {
			continue
		}
		switch key {
		case "Pss_Anon":
			mem.AnonBytes = kb << 10
			found = true
		case "Pss_File", "Pss_Shmem":
			mem.FileBytes += kb << 10
		}
	}
	return mem, found
}

// parseStatCPUTime sums utime and stime, fields 14 and 15 of a
// /proc/<pid>/stat line. Fields are counted from the last ')', since the
// command name in field 2 can hold spaces and parentheses.
func parseStatCPUTime(stat string) (time.Duration, bool) {
	end := strings.LastIndexByte(stat, ')')
	if end < 0 {
		return 0, false
	}
	fields := strings.Fields(stat[end+1:])
	if len(fields) < 13 {
		return 0, false
	}
	utime, err := strconv.ParseInt(fields[11], 10, 64)
	if err != nil {
		return 0, false
	}
	stime, err := strconv.ParseInt(fields[12], 10, 64)
	if err != nil {
		return 0, false
	}
	return time.Duration(utime+stime) * time.Second / userHZ, true
}

// ProcessStart is a process's start time in clock ticks since boot (field
// 22 of /proc/<pid>/stat), 0 where it cannot be read. With the pid it names
// one process: a pid the kernel reuses starts later.
func ProcessStart(pid int) uint64 {
	if pid <= 0 {
		return 0
	}
	data, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat")
	if err != nil {
		return 0
	}
	return parseStatStart(string(data))
}

func parseStatStart(stat string) uint64 {
	end := strings.LastIndexByte(stat, ')')
	if end < 0 {
		return 0
	}
	fields := strings.Fields(stat[end+1:])
	if len(fields) < 20 {
		return 0
	}
	start, err := strconv.ParseUint(fields[19], 10, 64)
	if err != nil {
		return 0
	}
	return start
}
