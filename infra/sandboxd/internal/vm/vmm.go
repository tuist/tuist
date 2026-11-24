package vm

// The vmm container spawns Firecracker for the daemon, so the VMs sit in its
// cgroup and survive a restart of the daemon's container (step 2b; for now a
// VM still ends with the daemon's connection). The daemon asks over a unix
// socket on a volume the two containers share: one connection per VM, which
// carries the spec and, as SCM_RIGHTS, the daemon's mount namespace and the
// VM's cgroup. VMMServer spawns the jailer inside that mount namespace, so it
// sees the network namespaces and lazy-disk mounts the daemon made, and holds
// Firecracker's output pipe and firecracker.log. The pod shares one PID
// namespace, so the daemon reads /proc/<pid> as it does for its own VMs.

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
)

const maxVMMMessage = 64 << 10

type vmmRequest struct {
	Op string `json:"op"`
	// Launch only: the spec, and whether a cgroup fd follows the mount
	// namespace's.
	Spec   *Spec `json:"spec,omitempty"`
	Cgroup bool  `json:"cgroup,omitempty"`
}

type vmmReply struct {
	// Hello: the vmm container's cgroup, under which the daemon creates the
	// VMs' cgroups and whose memory limit the server resizes.
	Cgroup string `json:"cgroup,omitempty"`
	Error  string `json:"error,omitempty"`
	PID    int    `json:"pid,omitempty"`
	Exited bool   `json:"exited,omitempty"`
	Exit   string `json:"exit,omitempty"`
}

// VMMServer is the vmm container's side.
type VMMServer struct {
	Launcher Launcher
	Cgroup   string
	Log      *slog.Logger
	// LaunchTimeout bounds a spawn up to Firecracker's API answering.
	LaunchTimeout time.Duration

	active atomic.Int64
}

// Active counts the VMs vmm holds, launching or running. On SIGTERM vmm
// waits for it to reach zero: both containers stop together, and the
// daemon pauses its VMs first, which needs them alive.
func (s *VMMServer) Active() int64 { return s.active.Load() }

func (s *VMMServer) Serve(ln *net.UnixListener) error {
	for {
		conn, err := ln.AcceptUnix()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return nil
			}
			return err
		}
		go s.handle(conn)
	}
}

func (s *VMMServer) handle(conn *net.UnixConn) {
	defer conn.Close()
	req, files, rest, err := readVMMRequest(conn)
	defer closeFiles(files)
	if err != nil {
		s.Log.Warn("vmm: unreadable request", "error", err)
		return
	}
	switch req.Op {
	case "hello":
		// The daemon keeps this connection open: its end tells the daemon
		// that vmm, and every VM it held, is gone.
		if writeVMM(conn, vmmReply{Cgroup: s.Cgroup}) == nil {
			_, _ = io.Copy(io.Discard, rest)
		}
	case "launch":
		s.active.Add(1)
		defer s.active.Add(-1)
		s.launch(conn, req, files, rest)
	default:
		_ = writeVMM(conn, vmmReply{Error: fmt.Sprintf("unknown op %q", req.Op)})
	}
}

func (s *VMMServer) launch(conn *net.UnixConn, req vmmRequest, files []*os.File, rest *bufio.Reader) {
	want := 1
	if req.Cgroup {
		want = 2
	}
	if req.Spec == nil || len(files) != want {
		_ = writeVMM(conn, vmmReply{Error: fmt.Sprintf("launch needs a spec and %d fds, got %d", want, len(files))})
		return
	}
	spec := *req.Spec
	spec.MountNS = files[0]
	if req.Cgroup {
		spec.Cgroup = files[1]
	}
	timeout := s.LaunchTimeout
	if timeout == 0 {
		timeout = 2 * time.Minute
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	inst, err := s.Launcher.Launch(ctx, spec)
	cancel()
	if err != nil {
		_ = writeVMM(conn, vmmReply{Error: err.Error()})
		return
	}
	log := s.Log.With("vm", spec.ID, "pid", inst.PID())
	log.Info("vmm: spawned")
	if err := writeVMM(conn, vmmReply{PID: inst.PID()}); err != nil {
		log.Warn("vmm: daemon gone before the reply; killing", "error", err)
	}
	// A VM lives as long as the daemon's connection for it: a daemon that
	// stopped without pausing it treats it as dead and cold boots it on its
	// next resume, which must not find this one still running.
	go func() {
		dec := json.NewDecoder(rest)
		for {
			var msg vmmRequest
			if err := dec.Decode(&msg); err != nil || msg.Op == "kill" {
				break
			}
		}
		killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = inst.Kill(killCtx)
	}()
	<-inst.Done()
	exit := ""
	if err := inst.ExitError(); err != nil {
		exit = err.Error()
	}
	log.Info("vmm: exited", "exit", exit)
	_ = writeVMM(conn, vmmReply{Exited: true, Exit: exit})
}

// VMMCgroup asks the vmm container for its cgroup, retrying until it
// listens or ctx ends: the two containers start together. gone closes when
// that vmm stops: its VMs died with it, and a restarted vmm has another
// cgroup, so the daemon has to start over.
func VMMCgroup(ctx context.Context, socket string) (cgroup string, gone <-chan struct{}, err error) {
	for {
		conn, reply, err := vmmHello(ctx, socket)
		if err == nil {
			if reply.Error != "" {
				conn.Close()
				return "", nil, errors.New(reply.Error)
			}
			done := make(chan struct{})
			go func() {
				_, _ = io.Copy(io.Discard, conn)
				conn.Close()
				close(done)
			}()
			return reply.Cgroup, done, nil
		}
		select {
		case <-ctx.Done():
			return "", nil, fmt.Errorf("vmm at %s: %w", socket, err)
		case <-time.After(500 * time.Millisecond):
		}
	}
}

func vmmHello(ctx context.Context, socket string) (*net.UnixConn, vmmReply, error) {
	conn, err := dialVMM(ctx, socket)
	if err != nil {
		return nil, vmmReply{}, err
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	if err := sendVMM(conn, vmmRequest{Op: "hello"}, nil); err != nil {
		conn.Close()
		return nil, vmmReply{}, err
	}
	// vmm writes nothing after the reply, so the decoder buffers nothing.
	var reply vmmReply
	if err := json.NewDecoder(conn).Decode(&reply); err != nil {
		conn.Close()
		return nil, vmmReply{}, err
	}
	_ = conn.SetDeadline(time.Time{})
	return conn, reply, nil
}

// VMMLauncher is the daemon's side: a Launcher that has the vmm container
// spawn each VM.
type VMMLauncher struct {
	Socket string
	Log    *slog.Logger
}

func (l *VMMLauncher) Launch(ctx context.Context, spec Spec) (Instance, error) {
	if err := ValidateID(spec.ID); err != nil {
		return nil, err
	}
	mntns, err := os.Open("/proc/self/ns/mnt")
	if err != nil {
		return nil, fmt.Errorf("opening the daemon's mount namespace: %w", err)
	}
	defer mntns.Close()
	files := []*os.File{mntns}
	if spec.Cgroup != nil {
		files = append(files, spec.Cgroup)
	}
	conn, err := dialVMM(ctx, l.Socket)
	if err != nil {
		return nil, err
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	stop := context.AfterFunc(ctx, func() { _ = conn.SetDeadline(time.Now()) })
	defer stop()
	if err := sendVMM(conn, vmmRequest{Op: "launch", Spec: &spec, Cgroup: spec.Cgroup != nil}, files); err != nil {
		conn.Close()
		return nil, fmt.Errorf("asking vmm to launch %s: %w", spec.ID, err)
	}
	dec := json.NewDecoder(conn)
	var reply vmmReply
	if err := dec.Decode(&reply); err != nil {
		conn.Close()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("vmm launch of %s: %w", spec.ID, err)
	}
	if reply.Error != "" || reply.PID <= 0 {
		conn.Close()
		return nil, fmt.Errorf("vmm launch of %s: %s", spec.ID, reply.Error)
	}
	if !stop() {
		conn.Close()
		return nil, ctx.Err()
	}
	_ = conn.SetDeadline(time.Time{})
	root := RootDir(spec.JailBase, spec.ID)
	logger := l.Log
	if logger == nil {
		logger = slog.Default()
	}
	m := &remoteMachine{
		spec:   spec,
		root:   root,
		client: firecracker.NewClient(filepath.Join(root, firecracker.APISocketPath)),
		log:    logger.With("vm", spec.ID),
		conn:   conn,
		pid:    reply.PID,
		done:   make(chan struct{}),
	}
	go m.watch(dec)
	return m, nil
}

type remoteMachine struct {
	spec   Spec
	root   string
	client *firecracker.Client
	log    *slog.Logger
	conn   *net.UnixConn
	pid    int

	writeMu sync.Mutex
	killed  atomic.Bool
	done    chan struct{}
	exitMu  sync.Mutex
	exitErr error
}

// watch waits for vmm's exit report. A connection that breaks first means
// vmm is gone, and the VMs in its cgroup with it.
func (m *remoteMachine) watch(dec *json.Decoder) {
	var reply vmmReply
	var err error
	for {
		if err = dec.Decode(&reply); err != nil || reply.Exited {
			break
		}
	}
	switch {
	case err != nil:
		err = fmt.Errorf("lost vmm: %w", err)
	case reply.Exit != "":
		err = errors.New(reply.Exit)
	}
	m.exitMu.Lock()
	if m.killed.Load() && err != nil {
		err = fmt.Errorf("killed by sandboxd (%v)", err)
	}
	m.exitErr = err
	m.exitMu.Unlock()
	m.conn.Close()
	close(m.done)
}

func (m *remoteMachine) ID() string                    { return m.spec.ID }
func (m *remoteMachine) Root() string                  { return m.root }
func (m *remoteMachine) HostPath(inJail string) string { return filepath.Join(m.root, inJail) }
func (m *remoteMachine) API() *firecracker.Client      { return m.client }
func (m *remoteMachine) VsockPath() string             { return m.HostPath(firecracker.VsockPath) }
func (m *remoteMachine) PID() int                      { return m.pid }
func (m *remoteMachine) Done() <-chan struct{}         { return m.done }
func (m *remoteMachine) Killed() bool                  { return m.killed.Load() }

func (m *remoteMachine) GuestPath(inJail string) string {
	if m.spec.JailerEnabled {
		return inJail
	}
	return m.HostPath(inJail)
}

func (m *remoteMachine) ExitError() error {
	m.exitMu.Lock()
	defer m.exitMu.Unlock()
	return m.exitErr
}

func (m *remoteMachine) CPUTime() (time.Duration, bool) { return vcpuCPUTime("/proc", m.pid) }
func (m *remoteMachine) ResidentMemory() (Memory, bool) { return processMemory(m.pid) }

// Kill asks vmm to kill the VM and waits for its exit report. The SIGKILL
// is a backstop for a vmm that stopped answering; the pod shares one PID
// namespace.
func (m *remoteMachine) Kill(ctx context.Context) error {
	m.killed.Store(true)
	select {
	case <-m.done:
		return nil
	default:
	}
	m.writeMu.Lock()
	err := writeVMM(m.conn, vmmRequest{Op: "kill"})
	m.writeMu.Unlock()
	if err != nil {
		_ = syscall.Kill(m.pid, syscall.SIGKILL)
	}
	select {
	case <-m.done:
		return nil
	case <-ctx.Done():
		_ = syscall.Kill(m.pid, syscall.SIGKILL)
		return fmt.Errorf("waiting for firecracker %d to die: %w", m.pid, ctx.Err())
	}
}

func dialVMM(ctx context.Context, socket string) (*net.UnixConn, error) {
	var d net.Dialer
	conn, err := d.DialContext(ctx, "unix", socket)
	if err != nil {
		return nil, err
	}
	return conn.(*net.UnixConn), nil
}

func writeVMM(conn *net.UnixConn, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	_, err = conn.Write(append(data, '\n'))
	return err
}

// sendVMM writes one request with its fds in a single sendmsg, so they
// arrive with its first byte.
func sendVMM(conn *net.UnixConn, req vmmRequest, files []*os.File) error {
	data, err := json.Marshal(req)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if len(data) > maxVMMMessage {
		return fmt.Errorf("vmm request of %d bytes is over %d", len(data), maxVMMMessage)
	}
	var oob []byte
	if len(files) > 0 {
		fds := make([]int, len(files))
		for i, f := range files {
			fds[i] = int(f.Fd()) //nolint:gosec // fds fit an int.
		}
		oob = unix.UnixRights(fds...)
	}
	n, _, err := conn.WriteMsgUnix(data, oob, nil)
	if err == nil && n < len(data) {
		_, err = conn.Write(data[n:])
	}
	return err
}

// readVMMRequest reads the first request and the fds that came with it. The
// reader it returns carries what follows on the connection.
func readVMMRequest(conn *net.UnixConn) (vmmRequest, []*os.File, *bufio.Reader, error) {
	buf := make([]byte, maxVMMMessage)
	oob := make([]byte, unix.CmsgSpace(4*4))
	n, oobn, _, _, err := conn.ReadMsgUnix(buf, oob)
	if err != nil {
		return vmmRequest{}, nil, nil, err
	}
	var files []*os.File
	if oobn > 0 {
		msgs, err := unix.ParseSocketControlMessage(oob[:oobn])
		if err != nil {
			return vmmRequest{}, nil, nil, err
		}
		for _, msg := range msgs {
			fds, err := unix.ParseUnixRights(&msg)
			if err != nil {
				continue
			}
			for _, fd := range fds {
				files = append(files, os.NewFile(uintptr(fd), fmt.Sprintf("vmm-fd-%d", fd))) //nolint:gosec // fds are non-negative.
			}
		}
	}
	// The request is the first line; a request longer than one read
	// continues on the connection.
	reader := bufio.NewReader(conn)
	line := buf[:n]
	for len(line) == 0 || line[len(line)-1] != '\n' {
		more, err := reader.ReadSlice('\n')
		line = append(line, more...)
		if err != nil {
			closeFiles(files)
			return vmmRequest{}, nil, nil, err
		}
		if len(line) > maxVMMMessage {
			closeFiles(files)
			return vmmRequest{}, nil, nil, errors.New("vmm request too long")
		}
	}
	var req vmmRequest
	if err := json.Unmarshal(line, &req); err != nil {
		closeFiles(files)
		return vmmRequest{}, nil, nil, err
	}
	return req, files, reader, nil
}

func closeFiles(files []*os.File) {
	for _, f := range files {
		_ = f.Close()
	}
}
