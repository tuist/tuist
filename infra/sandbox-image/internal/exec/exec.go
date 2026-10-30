// Package exec runs host-requested commands in the guest, streams their output
// and tracks them by id so a later kill request can reach a running one.
package exec

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	osexec "os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

// ExitTimeout is reported when the command outlived its timeout and was
// killed, mirroring timeout(1).
const ExitTimeout = 124

// outputGrace bounds how long a finished command's output pipes are drained
// after it exits, so a backgrounded child that inherited them cannot hold the
// exec open forever.
const outputGrace = 2 * time.Second

var ErrNotFound = errors.New("no running exec with that id")

// DefaultEnv is the environment every command starts from; the request's env
// is merged on top.
var DefaultEnv = map[string]string{
	"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
	"HOME": "/root",
	"LANG": "C.UTF-8",
}

type Spec struct {
	Cmd     []string
	Env     map[string]string
	Cwd     string
	Timeout time.Duration
}

type Stream string

const (
	Stdout Stream = "stdout"
	Stderr Stream = "stderr"
)

// Output receives command output as it is produced. Write is called from one
// goroutine per stream, so implementations must be safe for concurrent use. A
// write error means the peer is gone: the command is killed.
type Output interface {
	Write(stream Stream, data []byte) error
}

// Registry runs commands and remembers the running ones by id.
type Registry struct {
	DefaultCwd string
	DefaultEnv map[string]string

	mu    sync.Mutex
	procs map[string]*os.Process
}

func NewRegistry(defaultCwd string) *Registry {
	return &Registry{DefaultCwd: defaultCwd, DefaultEnv: DefaultEnv, procs: map[string]*os.Process{}}
}

// Run starts the command, calls started with its id once it is running,
// streams its output to out and returns its exit code. An error is returned
// only when the command could not be started.
func (r *Registry) Run(ctx context.Context, spec Spec, started func(id string), out Output) (int, error) {
	if len(spec.Cmd) == 0 {
		return 0, errors.New("cmd is empty")
	}
	cwd := spec.Cwd
	if cwd == "" {
		cwd = r.DefaultCwd
	}
	if info, err := os.Stat(cwd); err != nil {
		return 0, fmt.Errorf("cwd: %w", err)
	} else if !info.IsDir() {
		return 0, fmt.Errorf("cwd: %s is not a directory", cwd)
	}
	env := mergeEnv(r.DefaultEnv, spec.Env)
	path, err := lookPath(spec.Cmd[0], envValue(env, "PATH"))
	if err != nil {
		return 0, err
	}

	stdoutR, stdoutW, err := os.Pipe()
	if err != nil {
		return 0, err
	}
	stderrR, stderrW, err := os.Pipe()
	if err != nil {
		stdoutR.Close()
		stdoutW.Close()
		return 0, err
	}

	cmd := &osexec.Cmd{
		Path:   path,
		Args:   spec.Cmd,
		Dir:    cwd,
		Env:    env,
		Stdout: stdoutW,
		Stderr: stderrW,
		// A process group of its own so timeouts and kills reach the whole tree.
		SysProcAttr: &syscall.SysProcAttr{Setpgid: true},
	}
	err = cmd.Start()
	stdoutW.Close()
	stderrW.Close()
	if err != nil {
		stdoutR.Close()
		stderrR.Close()
		return 0, err
	}
	id := r.register(cmd.Process)
	defer r.unregister(id)
	if started != nil {
		started(id)
	}

	pumpErr := make(chan error, 2)
	var pumps sync.WaitGroup
	pumps.Add(2)
	go pump(&pumps, Stdout, stdoutR, out, pumpErr)
	go pump(&pumps, Stderr, stderrR, out, pumpErr)

	waitDone := make(chan error, 1)
	go func() { waitDone <- cmd.Wait() }()

	var timeout <-chan time.Time
	if spec.Timeout > 0 {
		timer := time.NewTimer(spec.Timeout)
		defer timer.Stop()
		timeout = timer.C
	}

	var (
		waitErr  error
		timedOut bool
		sinkErr  error
	)
	for waitErr == nil {
		select {
		case waitErr = <-waitDone:
			if waitErr == nil {
				waitErr = errDone
			}
		case <-timeout:
			timedOut = true
			timeout = nil
			killGroup(cmd.Process.Pid, syscall.SIGKILL)
		case <-ctx.Done():
			killGroup(cmd.Process.Pid, syscall.SIGKILL)
			waitErr = <-waitDone
			if waitErr == nil {
				waitErr = errDone
			}
		case sinkErr = <-pumpErr:
			pumpErr = nil
			killGroup(cmd.Process.Pid, syscall.SIGKILL)
		}
	}
	if waitErr == errDone {
		waitErr = nil
	}

	drained := make(chan struct{})
	go func() {
		pumps.Wait()
		close(drained)
	}()
	select {
	case <-drained:
	case <-time.After(outputGrace):
		stdoutR.Close()
		stderrR.Close()
		<-drained
	}
	stdoutR.Close()
	stderrR.Close()

	if sinkErr != nil {
		return exitCode(waitErr, timedOut), sinkErr
	}
	return exitCode(waitErr, timedOut), nil
}

// errDone marks a clean wait inside the select loop, where nil means "still
// running".
var errDone = errors.New("done")

// Kill signals the exec's whole process group.
func (r *Registry) Kill(id string, sig syscall.Signal) error {
	r.mu.Lock()
	proc, ok := r.procs[id]
	r.mu.Unlock()
	if !ok {
		return ErrNotFound
	}
	return killGroup(proc.Pid, sig)
}

// Running lists the ids of commands that have not exited yet.
func (r *Registry) Running() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	ids := make([]string, 0, len(r.procs))
	for id := range r.procs {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

func (r *Registry) register(proc *os.Process) string {
	var raw [6]byte
	if _, err := rand.Read(raw[:]); err != nil {
		panic(err)
	}
	id := "e-" + hex.EncodeToString(raw[:])
	r.mu.Lock()
	r.procs[id] = proc
	r.mu.Unlock()
	return id
}

func (r *Registry) unregister(id string) {
	r.mu.Lock()
	delete(r.procs, id)
	r.mu.Unlock()
}

func pump(wg *sync.WaitGroup, stream Stream, f *os.File, out Output, errs chan<- error) {
	defer wg.Done()
	buf := make([]byte, 32<<10)
	for {
		n, err := f.Read(buf)
		if n > 0 {
			if werr := out.Write(stream, buf[:n]); werr != nil {
				errs <- werr
				return
			}
		}
		if err != nil {
			return
		}
	}
}

func killGroup(pid int, sig syscall.Signal) error {
	if err := syscall.Kill(-pid, sig); err != nil {
		if errors.Is(err, syscall.ESRCH) {
			return nil
		}
		return err
	}
	return nil
}

func exitCode(waitErr error, timedOut bool) int {
	if timedOut {
		return ExitTimeout
	}
	if waitErr == nil {
		return 0
	}
	var exitErr *osexec.ExitError
	if errors.As(waitErr, &exitErr) {
		if status, ok := exitErr.Sys().(syscall.WaitStatus); ok && status.Signaled() {
			return 128 + int(status.Signal())
		}
		return exitErr.ExitCode()
	}
	return -1
}

func mergeEnv(base, extra map[string]string) []string {
	merged := make(map[string]string, len(base)+len(extra))
	for k, v := range base {
		merged[k] = v
	}
	for k, v := range extra {
		merged[k] = v
	}
	keys := make([]string, 0, len(merged))
	for k := range merged {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	env := make([]string, 0, len(keys))
	for _, k := range keys {
		env = append(env, k+"="+merged[k])
	}
	return env
}

func envValue(env []string, key string) string {
	for _, kv := range env {
		if v, ok := strings.CutPrefix(kv, key+"="); ok {
			return v
		}
	}
	return ""
}

// lookPath resolves a bare command name against the command's own PATH rather
// than the agent's, so a request that sets PATH sees it honoured.
func lookPath(name, pathEnv string) (string, error) {
	if strings.Contains(name, "/") {
		if err := executable(name); err != nil {
			return "", err
		}
		return name, nil
	}
	for _, dir := range filepath.SplitList(pathEnv) {
		if dir == "" {
			dir = "."
		}
		candidate := filepath.Join(dir, name)
		if err := executable(candidate); err == nil {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("%s: executable not found in PATH", name)
}

func executable(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if info.IsDir() || info.Mode()&0o111 == 0 {
		return fmt.Errorf("%s: not an executable file", path)
	}
	return nil
}
