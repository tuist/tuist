package vm

// The vmm container spawns Firecracker for the daemon, so the VMs sit in its
// cgroup and can outlive the daemon's container. The daemon asks over a unix
// socket on a volume the two containers share: one connection per VM, which
// carries the spec and, as SCM_RIGHTS, the daemon's mount namespace and the
// VM's cgroup. A VM lives as long as its connection unless the daemon
// detaches it first, for an in-place upgrade of the daemon (step 2b); the
// next daemon then attaches it by id and pid. VMMServer spawns the jailer inside that mount namespace, so it
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
	// Attach only: the VM and the process the daemon recorded for it.
	ID  string `json:"id,omitempty"`
	PID int    `json:"pid,omitempty"`
}

type vmmReply struct {
	// Hello: the vmm container's cgroup, under which the daemon creates the
	// VMs' cgroups and whose memory limit the server resizes, and the
	// version of the Firecracker it spawns.
	Cgroup             string `json:"cgroup,omitempty"`
	FirecrackerVersion string `json:"firecracker_version,omitempty"`
	Error              string `json:"error,omitempty"`
	PID                int    `json:"pid,omitempty"`
	// Start is the process's start time (/proc/<pid>/stat), which with the
	// pid names one process for the daemon that attaches to it.
	Start    uint64  `json:"start,omitempty"`
	Exited   bool    `json:"exited,omitempty"`
	Exit     string  `json:"exit,omitempty"`
	Detached bool    `json:"detached,omitempty"`
	VMs      []VMMVM `json:"vms,omitempty"`
}

// VMMVM is a VM the vmm container holds.
type VMMVM struct {
	ID     string `json:"id"`
	PID    int    `json:"pid"`
	Start  uint64 `json:"start"`
	Exited bool   `json:"exited,omitempty"`
	// Detached: no daemon holds it; it waits for the next one to attach.
	Detached bool `json:"detached,omitempty"`
}

// VMMServer is the vmm container's side.
type VMMServer struct {
	Launcher           Launcher
	Cgroup             string
	FirecrackerVersion string
	// FirecrackerBin and JailerBin, when set, replace the daemon's paths in
	// every spec: this container's binaries, reached through
	// /proc/<vmm pid>/root from the daemon's mount namespace, so an upgrade
	// of the daemon's image never changes the Firecracker its VMs run.
	FirecrackerBin, JailerBin string
	Log                       *slog.Logger
	// LaunchTimeout bounds a spawn up to Firecracker's API answering.
	LaunchTimeout time.Duration
	// DetachTTL is how long a detached VM waits for a daemon to attach it
	// before vmm kills it (default 10 minutes): its disks moved on since its
	// last memory image, so a daemon that never came back cold boots it, and
	// must not find it still running.
	DetachTTL time.Duration

	active   atomic.Int64
	mu       sync.Mutex
	vms      map[string]*heldVM
	draining bool
}

// heldVM is one VM vmm spawned. conn is the daemon connection it belongs
// to, nil while detached; a VM whose connection ends without a detach is
// killed.
type heldVM struct {
	id    string
	inst  Instance
	start uint64
	log   *slog.Logger

	// Guarded by VMMServer.mu.
	conn     *vmmConn
	exited   bool
	exit     string
	timer    *time.Timer
	reported chan struct{}
}

type vmmConn struct {
	conn *net.UnixConn
	mu   sync.Mutex
}

func (c *vmmConn) write(v any) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return writeVMM(c.conn, v)
}

// Active counts the VMs vmm holds, launching or running, detached or not.
// On SIGTERM vmm waits for it to reach zero: both containers stop together,
// and the daemon pauses its VMs first, which needs them alive.
func (s *VMMServer) Active() int64 { return s.active.Load() }

// Drain is for vmm's own SIGTERM: the Pod is going away. Detaches are
// refused from now on, so a daemon pauses its VMs instead, and a VM still
// detached is killed after grace unless a daemon attaches it first (the
// next daemon pauses it on its own shutdown).
func (s *VMMServer) Drain(grace time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.draining = true
	for _, h := range s.vms {
		if h.conn == nil && !h.exited {
			s.expireAfter(h, grace)
		}
	}
}

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
		if writeVMM(conn, vmmReply{Cgroup: s.Cgroup, FirecrackerVersion: s.FirecrackerVersion}) == nil {
			_, _ = io.Copy(io.Discard, rest)
		}
	case "list":
		_ = writeVMM(conn, vmmReply{VMs: s.list()})
	case "launch":
		s.launch(conn, req, files, rest)
	case "attach":
		s.attach(conn, req, rest)
	default:
		_ = writeVMM(conn, vmmReply{Error: fmt.Sprintf("unknown op %q", req.Op)})
	}
}

func (s *VMMServer) list() []VMMVM {
	s.mu.Lock()
	defer s.mu.Unlock()
	vms := make([]VMMVM, 0, len(s.vms))
	for _, h := range s.vms {
		vms = append(vms, VMMVM{ID: h.id, PID: h.inst.PID(), Start: h.start, Exited: h.exited, Detached: h.conn == nil})
	}
	return vms
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
	if s.FirecrackerBin != "" {
		spec.FirecrackerBin = s.FirecrackerBin
	}
	if s.JailerBin != "" {
		spec.JailerBin = s.JailerBin
	}
	s.mu.Lock()
	if old := s.vms[spec.ID]; old != nil && !old.exited {
		s.mu.Unlock()
		// A detached VM of this id still runs: the daemon kills it (attach,
		// then kill) before it spawns another.
		_ = writeVMM(conn, vmmReply{Error: fmt.Sprintf("vm %s is still running", spec.ID)})
		return
	}
	s.mu.Unlock()
	s.active.Add(1)
	timeout := s.LaunchTimeout
	if timeout == 0 {
		timeout = 2 * time.Minute
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	inst, err := s.Launcher.Launch(ctx, spec)
	cancel()
	if err != nil {
		s.active.Add(-1)
		_ = writeVMM(conn, vmmReply{Error: err.Error()})
		return
	}
	pid := inst.PID()
	h := &heldVM{id: spec.ID, inst: inst, start: ProcessStart(pid), log: s.Log.With("vm", spec.ID, "pid", pid), reported: make(chan struct{})}
	c := &vmmConn{conn: conn}
	h.log.Info("vmm: spawned")
	s.mu.Lock()
	h.conn = c
	if s.vms == nil {
		s.vms = make(map[string]*heldVM)
	}
	s.vms[spec.ID] = h
	// Under the lock, so the exit report cannot overtake it.
	err = c.write(vmmReply{PID: pid, Start: h.start})
	s.mu.Unlock()
	go s.reap(h)
	if err != nil {
		h.log.Warn("vmm: daemon gone before the reply; killing", "error", err)
	}
	s.serve(c, h, rest)
}

// attach hands a VM to a daemon connection: a detached one to the daemon
// that starts after an upgrade (step 2b), or one this daemon wants killed.
func (s *VMMServer) attach(conn *net.UnixConn, req vmmRequest, rest *bufio.Reader) {
	c := &vmmConn{conn: conn}
	s.mu.Lock()
	h := s.vms[req.ID]
	switch {
	case h == nil:
		s.mu.Unlock()
		_ = c.write(vmmReply{Error: fmt.Sprintf("vmm holds no vm %s", req.ID)})
		return
	case h.inst.PID() != req.PID:
		s.mu.Unlock()
		_ = c.write(vmmReply{Error: fmt.Sprintf("vm %s is pid %d, not %d", req.ID, h.inst.PID(), req.PID)})
		return
	case h.conn != nil:
		s.mu.Unlock()
		_ = c.write(vmmReply{Error: fmt.Sprintf("vm %s belongs to another connection", req.ID)})
		return
	case h.exited:
		delete(s.vms, h.id)
		s.mu.Unlock()
		_ = c.write(vmmReply{PID: req.PID, Start: h.start, Exited: true, Exit: h.exit})
		return
	}
	if h.timer != nil {
		h.timer.Stop()
		h.timer = nil
	}
	h.conn = c
	err := c.write(vmmReply{PID: req.PID, Start: h.start})
	s.mu.Unlock()
	h.log.Info("vmm: attached")
	if err != nil {
		h.log.Warn("vmm: daemon gone before the attach reply; killing", "error", err)
	}
	s.serve(c, h, rest)
}

// serve reads the bound daemon's messages until it kills the VM, detaches
// it, or goes away. A daemon that goes away without detaching treats the
// VM as dead and cold boots it on its next resume, which must not find this
// one still running, so it is killed.
func (s *VMMServer) serve(c *vmmConn, h *heldVM, rest *bufio.Reader) {
	dec := json.NewDecoder(rest)
	for {
		var msg vmmRequest
		if err := dec.Decode(&msg); err != nil || msg.Op == "kill" {
			break
		}
		if msg.Op != "detach" {
			continue
		}
		if s.detach(h, c) {
			_ = c.write(vmmReply{Detached: true})
			h.log.Info("vmm: detached; waiting for the next daemon")
			return
		}
		_ = c.write(vmmReply{Error: "vmm refuses the detach: it is stopping or the vm exited"})
	}
	killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	_ = h.inst.Kill(killCtx)
	// The exit report goes out before the connection closes.
	<-h.reported
}

func (s *VMMServer) detach(h *heldVM, c *vmmConn) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.draining || h.exited || h.conn != c {
		return false
	}
	h.conn = nil
	ttl := s.DetachTTL
	if ttl == 0 {
		ttl = 10 * time.Minute
	}
	s.expireAfter(h, ttl)
	return true
}

// expireAfter kills h after d unless a daemon attaches it first. Caller
// holds s.mu.
func (s *VMMServer) expireAfter(h *heldVM, d time.Duration) {
	if h.timer != nil {
		h.timer.Stop()
	}
	h.timer = time.AfterFunc(d, func() {
		s.mu.Lock()
		expired := h.conn == nil && !h.exited && s.vms[h.id] == h
		s.mu.Unlock()
		if !expired {
			return
		}
		h.log.Warn("vmm: no daemon attached the detached vm; killing it", "after", d)
		killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = h.inst.Kill(killCtx)
	})
}

// reap records h's exit and reports it to the daemon that holds it. A VM
// that exits detached stays listed, so the next daemon learns of the exit
// when it attaches, until the detach TTL drops it.
func (s *VMMServer) reap(h *heldVM) {
	<-h.inst.Done()
	exit := ""
	if err := h.inst.ExitError(); err != nil {
		exit = err.Error()
	}
	s.active.Add(-1)
	s.mu.Lock()
	h.exited, h.exit = true, exit
	c := h.conn
	if h.timer != nil {
		h.timer.Stop()
		h.timer = nil
	}
	if c != nil {
		if s.vms[h.id] == h {
			delete(s.vms, h.id)
		}
	} else {
		ttl := s.DetachTTL
		if ttl == 0 {
			ttl = 10 * time.Minute
		}
		h.timer = time.AfterFunc(ttl, func() {
			s.mu.Lock()
			if s.vms[h.id] == h {
				delete(s.vms, h.id)
			}
			s.mu.Unlock()
		})
	}
	s.mu.Unlock()
	h.log.Info("vmm: exited", "exit", exit, "detached", c == nil)
	if c != nil {
		_ = c.write(vmmReply{Exited: true, Exit: exit})
	}
	close(h.reported)
}

// VMMInfo is what the vmm container tells a daemon that connects.
type VMMInfo struct {
	// Cgroup is the container's, where the daemon creates the VMs' cgroups.
	Cgroup string
	// FirecrackerVersion is the Firecracker vmm spawns, empty from a vmm
	// older than step 2b, whose VMs run the daemon's binary.
	FirecrackerVersion string
}

// VMMHello asks the vmm container about itself, retrying until it listens
// or ctx ends: the two containers start together. gone closes when that vmm
// stops: its VMs died with it, and a restarted vmm has another cgroup, so
// the daemon has to start over.
func VMMHello(ctx context.Context, socket string) (info VMMInfo, gone <-chan struct{}, err error) {
	for {
		conn, reply, err := vmmHello(ctx, socket)
		if err == nil {
			if reply.Error != "" {
				conn.Close()
				return VMMInfo{}, nil, errors.New(reply.Error)
			}
			done := make(chan struct{})
			go func() {
				_, _ = io.Copy(io.Discard, conn)
				conn.Close()
				close(done)
			}()
			return VMMInfo{Cgroup: reply.Cgroup, FirecrackerVersion: reply.FirecrackerVersion}, done, nil
		}
		select {
		case <-ctx.Done():
			return VMMInfo{}, nil, fmt.Errorf("vmm at %s: %w", socket, err)
		case <-time.After(500 * time.Millisecond):
		}
	}
}

func vmmHello(ctx context.Context, socket string) (*net.UnixConn, vmmReply, error) {
	conn, reply, err := vmmCall(ctx, socket, vmmRequest{Op: "hello"})
	if err != nil {
		return nil, vmmReply{}, err
	}
	_ = conn.SetDeadline(time.Time{})
	return conn, reply, nil
}

// vmmCall sends one request without fds and reads the first reply. vmm
// writes nothing more on hello and list, so the decoder buffers nothing the
// caller would miss.
func vmmCall(ctx context.Context, socket string, req vmmRequest) (*net.UnixConn, vmmReply, error) {
	conn, err := dialVMM(ctx, socket)
	if err != nil {
		return nil, vmmReply{}, err
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	if err := sendVMM(conn, req, nil); err != nil {
		conn.Close()
		return nil, vmmReply{}, err
	}
	var reply vmmReply
	if err := json.NewDecoder(conn).Decode(&reply); err != nil {
		conn.Close()
		return nil, vmmReply{}, err
	}
	return conn, reply, nil
}

// Handoff is an instance the vmm container holds, which can outlive the
// daemon (step 2b): Detach leaves it running for the next daemon, which
// finds it by its pid and Start through an Attacher.
type Handoff interface {
	Detach(ctx context.Context) error
	Start() uint64
}

// Attacher finds the VMs a previous daemon detached and attaches them.
type Attacher interface {
	List(ctx context.Context) ([]VMMVM, error)
	// Attach binds the running VM spec.ID, process pid, to this daemon. A
	// VM that exited while detached returns ErrExited.
	Attach(ctx context.Context, spec Spec, pid int) (Instance, error)
}

// ErrExited is Attach's error for a VM that exited while no daemon held
// it.
var ErrExited = errors.New("the vm exited while detached")

// errDetached ends a remoteMachine whose VM was handed to the next daemon.
var errDetached = errors.New("detached")

// VMMLauncher is the daemon's side: a Launcher that has the vmm container
// spawn each VM.
type VMMLauncher struct {
	Socket string
	Log    *slog.Logger
}

func (l *VMMLauncher) List(ctx context.Context) ([]VMMVM, error) {
	conn, reply, err := vmmCall(ctx, l.Socket, vmmRequest{Op: "list"})
	if err != nil {
		return nil, fmt.Errorf("listing vmm's vms: %w", err)
	}
	conn.Close()
	if reply.Error != "" {
		return nil, errors.New(reply.Error)
	}
	return reply.VMs, nil
}

func (l *VMMLauncher) Attach(ctx context.Context, spec Spec, pid int) (Instance, error) {
	if err := ValidateID(spec.ID); err != nil {
		return nil, err
	}
	conn, err := dialVMM(ctx, l.Socket)
	if err != nil {
		return nil, err
	}
	return l.bind(ctx, conn, spec, vmmRequest{Op: "attach", ID: spec.ID, PID: pid}, nil)
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
	return l.bind(ctx, conn, spec, vmmRequest{Op: "launch", Spec: &spec, Cgroup: spec.Cgroup != nil}, files)
}

// bind sends a launch or attach and turns vmm's reply into an instance
// that lives as long as conn.
func (l *VMMLauncher) bind(ctx context.Context, conn *net.UnixConn, spec Spec, req vmmRequest, files []*os.File) (Instance, error) {
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	stop := context.AfterFunc(ctx, func() { _ = conn.SetDeadline(time.Now()) })
	defer stop()
	if err := sendVMM(conn, req, files); err != nil {
		conn.Close()
		return nil, fmt.Errorf("asking vmm to %s %s: %w", req.Op, spec.ID, err)
	}
	dec := json.NewDecoder(conn)
	var reply vmmReply
	if err := dec.Decode(&reply); err != nil {
		conn.Close()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("vmm %s of %s: %w", req.Op, spec.ID, err)
	}
	if reply.Exited {
		conn.Close()
		if reply.Exit != "" {
			return nil, fmt.Errorf("%w: %s", ErrExited, reply.Exit)
		}
		return nil, ErrExited
	}
	if reply.Error != "" || reply.PID <= 0 {
		conn.Close()
		return nil, fmt.Errorf("vmm %s of %s: %s", req.Op, spec.ID, reply.Error)
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
		spec:     spec,
		root:     root,
		client:   firecracker.NewClient(filepath.Join(root, firecracker.APISocketPath)),
		log:      logger.With("vm", spec.ID),
		conn:     conn,
		pid:      reply.PID,
		start:    reply.Start,
		done:     make(chan struct{}),
		detached: make(chan error, 1),
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
	start  uint64

	writeMu  sync.Mutex
	killed   atomic.Bool
	done     chan struct{}
	detached chan error
	exitMu   sync.Mutex
	exitErr  error
}

// watch waits for vmm's exit report, or its answer to a detach. A
// connection that breaks first means vmm is gone, and the VMs in its cgroup
// with it.
func (m *remoteMachine) watch(dec *json.Decoder) {
	var reply vmmReply
	var err error
	for {
		if err = dec.Decode(&reply); err != nil || reply.Exited || reply.Detached {
			break
		}
		if reply.Error != "" {
			// A refused detach: the VM stays ours.
			m.detached <- errors.New(reply.Error)
		}
	}
	switch {
	case err != nil:
		err = fmt.Errorf("lost vmm: %w", err)
	case reply.Detached:
		err = errDetached
	case reply.Exit != "":
		err = errors.New(reply.Exit)
	}
	m.exitMu.Lock()
	if m.killed.Load() && err != nil && !errors.Is(err, errDetached) {
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
func (m *remoteMachine) Start() uint64                 { return m.start }
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

// Detach hands the VM to vmm to keep running after this daemon exits.
// Done closes once vmm took it. A refusal (vmm is stopping) leaves the VM
// with this daemon; an exit first returns the exit.
func (m *remoteMachine) Detach(ctx context.Context) error {
	select {
	case <-m.done:
		return fmt.Errorf("the vm already exited: %w", m.ExitError())
	default:
	}
	m.writeMu.Lock()
	err := writeVMM(m.conn, vmmRequest{Op: "detach"})
	m.writeMu.Unlock()
	if err != nil {
		return fmt.Errorf("asking vmm to detach %s: %w", m.spec.ID, err)
	}
	select {
	case err := <-m.detached:
		return err
	case <-m.done:
		if err := m.ExitError(); !errors.Is(err, errDetached) {
			return fmt.Errorf("the vm exited instead of detaching: %w", err)
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

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
