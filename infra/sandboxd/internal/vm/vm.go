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
)

const (
	LogFileName = "firecracker.log"
	pidFileName = "firecracker.pid"
	// DefaultNetNSDir is where `ip netns add` mounts namespaces.
	DefaultNetNSDir = "/var/run/netns"
)

// idPattern is the jailer's constraint on --id.
var idPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9-]{0,63}$`)

func ValidateID(id string) error {
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
}

// Instance is a spawned Firecracker process.
type Instance interface {
	ID() string
	Root() string
	HostPath(inJail string) string
	GuestPath(inJail string) string
	API() *firecracker.Client
	VsockPath() string
	PID() int
	Done() <-chan struct{}
	ExitError() error
	Kill(ctx context.Context) error
}

type Launcher interface {
	Launch(ctx context.Context, spec Spec) (Instance, error)
}

// RootDir is the jail root the jailer builds for an id.
func RootDir(base, id string) string {
	return filepath.Join(base, "firecracker", id, "root")
}

// JailDir is the per-id directory above the root (holds the pid file and
// the exec copy).
func JailDir(base, id string) string {
	return filepath.Join(base, "firecracker", id)
}

// Prepare creates the jail root for a spawn and removes what a previous
// Firecracker left behind: the API and vsock sockets (Firecracker will not
// bind over an existing file) and the whole /dev tree, because the jailer
// mknods kvm, net/tun, urandom and userfaultfd itself and fails on EEXIST.
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

// Command builds the argv for a spec. Exported for tests.
func Command(spec Spec) []string {
	root := RootDir(spec.JailBase, spec.ID)
	nsDir := spec.NetNSDir
	if nsDir == "" {
		nsDir = DefaultNetNSDir
	}
	if spec.JailerEnabled {
		args := []string{
			spec.JailerBin,
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
		return args
	}
	var args []string
	if spec.NetNS != "" {
		args = append(args, "ip", "netns", "exec", spec.NetNS)
	}
	return append(args, spec.FirecrackerBin, "--id", spec.ID, "--api-sock", filepath.Join(root, firecracker.APISocketPath))
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
	logFile *os.File
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
	logFile, err := os.OpenFile(filepath.Join(root, LogFileName), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return nil, err
	}
	argv := Command(spec)
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Dir = root
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	fmt.Fprintf(logFile, "\n==== %s sandboxd spawn: %s\n", time.Now().UTC().Format(time.RFC3339), strings.Join(argv, " "))
	if err := cmd.Start(); err != nil {
		logFile.Close()
		return nil, fmt.Errorf("starting %s: %w", argv[0], err)
	}
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
				m.finish(fmt.Errorf("jailer: %w: %s", err, m.LogTail(2048)))
				logFile.Close()
				return nil, m.ExitError()
			}
		case <-time.After(timeout):
			m.log.Warn("jailer parent still running; continuing")
		case <-ctx.Done():
			_ = m.Kill(context.Background())
			return nil, ctx.Err()
		}
		pid, err := readPIDFile(filepath.Join(root, pidFileName))
		if err != nil {
			_ = m.Kill(context.Background())
			return nil, fmt.Errorf("reading firecracker pid: %w: %s", err, m.LogTail(2048))
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
			return nil, fmt.Errorf("firecracker exited before its API came up: %w: %s", m.ExitError(), m.LogTail(2048))
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
	f, err := os.Open(path)
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
