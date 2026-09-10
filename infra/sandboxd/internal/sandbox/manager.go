// Package sandbox is the node-side sandbox lifecycle: create from a template
// snapshot, pause to disk, resume, delete, exec and the worker process. One
// registry entry per sandbox with an on-disk metadata.json in its jail root.
package sandbox

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/network"
	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

const (
	DefaultWorkspaceGB     = 10
	DefaultBootTimeout     = 60 * time.Second
	DefaultWorkerPath      = "/usr/local/bin/sbx-worker"
	DefaultStopWorkerGrace = 30 * time.Second
	guestWorkspace         = "/workspace"
)

type Config struct {
	JailBase        string
	FirecrackerBin  string
	JailerBin       string
	JailerEnabled   bool
	UIDBase         int
	DNS             []string
	DefaultTemplate string
	BootTimeout     time.Duration
	WorkerPath      string
	StopWorkerGrace time.Duration
}

type Deps struct {
	Store    *template.Store
	Builder  *template.Builder
	Launcher vm.Launcher
	Network  network.Interface
	Slots    *network.Slots
	Agent    func(vsockPath string) vsock.Agent
	Metrics  *Metrics
	Events   func(protocol.Event)
	Log      *slog.Logger
}

type Manager struct {
	cfg      Config
	store    *template.Store
	builder  *template.Builder
	launcher vm.Launcher
	net      network.Interface
	slots    *network.Slots
	agent    func(string) vsock.Agent
	metrics  *Metrics
	events   func(protocol.Event)
	log      *slog.Logger

	mu        sync.Mutex
	sandboxes map[string]*Sandbox
}

type workerRun struct {
	proc    vsock.Process
	started time.Time
	done    chan struct{}
}

// Sandbox is one registry entry. opMu serializes lifecycle operations; mu
// guards the fields for readers.
type Sandbox struct {
	opMu sync.Mutex
	mu   sync.Mutex

	meta     Metadata
	root     string
	inst     vm.Instance
	agent    vsock.Agent
	worker   *workerRun
	inflight int
	// epoch changes on every spawn and deliberate kill so a death watcher
	// can tell whether the process it saw exit is still the current one.
	epoch uint64
}

var (
	ErrNotFound      = errors.New("sandbox not found")
	ErrAlreadyExists = errors.New("sandbox already exists")
	ErrNotRunning    = errors.New("sandbox is not running")
	ErrNotPaused     = errors.New("sandbox is not paused")
	ErrBusy          = errors.New("sandbox has a worker or exec running")
	ErrNoWorker      = errors.New("no worker running")
	ErrWorkerRunning = errors.New("worker already running")
)

func New(cfg Config, deps Deps) *Manager {
	if cfg.WorkerPath == "" {
		cfg.WorkerPath = DefaultWorkerPath
	}
	if cfg.BootTimeout == 0 {
		cfg.BootTimeout = DefaultBootTimeout
	}
	if cfg.StopWorkerGrace == 0 {
		cfg.StopWorkerGrace = DefaultStopWorkerGrace
	}
	if deps.Log == nil {
		deps.Log = slog.Default()
	}
	if deps.Agent == nil {
		deps.Agent = func(path string) vsock.Agent { return vsock.NewUDSClient(path, firecracker.AgentPort) }
	}
	if deps.Events == nil {
		deps.Events = func(protocol.Event) {}
	}
	return &Manager{
		cfg: cfg, store: deps.Store, builder: deps.Builder, launcher: deps.Launcher, net: deps.Network,
		slots: deps.Slots, agent: deps.Agent, metrics: deps.Metrics, events: deps.Events, log: deps.Log,
		sandboxes: map[string]*Sandbox{},
	}
}

func (m *Manager) get(id string) (*Sandbox, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	sb, ok := m.sandboxes[id]
	if !ok {
		return nil, fmt.Errorf("%w: %s", ErrNotFound, id)
	}
	return sb, nil
}

func (m *Manager) namespace(id string) string { return network.NamespaceName(id) }

// Create makes a sandbox from a template shape snapshot and boots it.
func (m *Manager) Create(ctx context.Context, args protocol.CreateArgs) (res protocol.CreateResult, err error) {
	start := time.Now()
	defer func() {
		m.metrics.observe(protocol.OpCreate, err)
		if err == nil && m.metrics != nil {
			m.metrics.Create.Observe(time.Since(start).Seconds())
		}
	}()
	if err := vm.ValidateID(args.SandboxID); err != nil {
		return res, err
	}
	shape := template.Shape{VCPUs: args.VCPUs, MemoryMB: args.MemoryMB}
	if err := shape.Validate(); err != nil {
		return res, err
	}
	if args.WorkspaceGB <= 0 {
		args.WorkspaceGB = DefaultWorkspaceGB
	}
	if args.Hostname == "" {
		args.Hostname = m.namespace(args.SandboxID)
	}
	name := args.Template
	if name == "" {
		name = m.cfg.DefaultTemplate
	}
	tmpl, err := m.store.Resolve(name, args.TemplateTag)
	if err != nil {
		return res, err
	}
	log := m.log.With("sandbox", args.SandboxID)

	root := vm.RootDir(m.cfg.JailBase, args.SandboxID)
	sb := &Sandbox{root: root, meta: Metadata{
		ID: args.SandboxID, Template: tmpl.Name, Tag: tmpl.Tag, VCPUs: shape.VCPUs, MemoryMB: shape.MemoryMB,
		WorkspaceGB: args.WorkspaceGB, Hostname: args.Hostname, State: "creating", Slot: -1, CreatedAt: time.Now().UTC(),
	}}
	m.mu.Lock()
	if _, exists := m.sandboxes[args.SandboxID]; exists {
		m.mu.Unlock()
		return res, fmt.Errorf("%w: %s", ErrAlreadyExists, args.SandboxID)
	}
	sb.opMu.Lock()
	m.sandboxes[args.SandboxID] = sb
	m.mu.Unlock()
	defer sb.opMu.Unlock()
	m.refreshGauges()

	defer func() {
		if err == nil {
			return
		}
		m.discard(sb)
	}()

	artifacts, err := m.builder.Ensure(ctx, tmpl, shape)
	if err != nil {
		return res, fmt.Errorf("template %s/%s %s: %w", tmpl.Name, tmpl.Tag, shape, err)
	}
	slot, err := m.slots.Allocate()
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	sb.meta.Slot = slot
	sb.mu.Unlock()
	uid := m.cfg.UIDBase + slot

	if err := os.RemoveAll(vm.JailDir(m.cfg.JailBase, args.SandboxID)); err != nil {
		return res, err
	}
	if err := vm.Prepare(root, uid, uid); err != nil {
		return res, err
	}
	if err := vm.HardLink(tmpl.Kernel(), filepath.Join(root, firecracker.KernelPath)); err != nil {
		return res, err
	}
	if err := vm.HardLink(artifacts.Memfile, filepath.Join(root, firecracker.MemPath)); err != nil {
		return res, err
	}
	if err := vm.HardLink(artifacts.Snapshot, filepath.Join(root, firecracker.SnapshotPath)); err != nil {
		return res, err
	}
	rootfs := filepath.Join(root, firecracker.RootfsPath)
	if err := vm.Reflink(artifacts.Rootfs, rootfs); err != nil {
		return res, err
	}
	if err := vm.Chown(rootfs, uid, uid); err != nil {
		return res, err
	}
	workspace := filepath.Join(root, firecracker.WorkspacePath)
	if err := vm.Sparse(workspace, int64(args.WorkspaceGB)<<30); err != nil {
		return res, err
	}
	if err := vm.Chown(workspace, uid, uid); err != nil {
		return res, err
	}

	bootStart := time.Now()
	inst, agent, err := m.restore(ctx, sb, log, func(api *firecracker.Client, inst vm.Instance) error {
		if args.WorkspaceGB == artifacts.Meta.WorkspaceGB {
			return nil
		}
		// The guest cached the template's workspace capacity at boot; a
		// drive patch makes Firecracker re-read the file size and notify
		// the guest before the agent formats it.
		return api.PatchDrive(ctx, firecracker.DrivePatch{DriveID: firecracker.WorkspaceDriveID, PathOnHost: inst.GuestPath(firecracker.WorkspacePath)})
	}, true)
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	sb.meta.State = protocol.StateRunning
	sb.meta.Generation = 0
	sb.meta.Error = ""
	err = sb.meta.Save(root)
	sb.mu.Unlock()
	if err != nil {
		return res, err
	}
	m.refreshGauges()
	log.Info("sandbox created", "template", tmpl.Name, "tag", tmpl.Tag, "shape", shape.String(), "slot", slot, "boot", time.Since(bootStart), "pid", inst.PID(), "agent", agent != nil)
	return protocol.CreateResult{BootMs: time.Since(bootStart).Milliseconds()}, nil
}

// restore spawns Firecracker for sb, loads /snapshot + /mem with resume and
// brings the guest agent up to date. beforeAgent runs after the load and
// before the agent handshake.
func (m *Manager) restore(ctx context.Context, sb *Sandbox, log *slog.Logger, beforeAgent func(*firecracker.Client, vm.Instance) error, formatWorkspace bool) (vm.Instance, vsock.Agent, error) {
	sb.mu.Lock()
	meta := sb.meta
	sb.mu.Unlock()
	ns := m.namespace(meta.ID)
	uid := m.cfg.UIDBase + meta.Slot
	if err := m.net.Setup(ctx, ns, meta.Slot); err != nil {
		return nil, nil, fmt.Errorf("network setup: %w", err)
	}
	inst, err := m.launcher.Launch(ctx, vm.Spec{
		ID: meta.ID, JailBase: m.cfg.JailBase, FirecrackerBin: m.cfg.FirecrackerBin, JailerBin: m.cfg.JailerBin,
		JailerEnabled: m.cfg.JailerEnabled, UID: uid, GID: uid, NetNS: ns,
	})
	if err != nil {
		_ = m.net.Teardown(context.Background(), ns, meta.Slot)
		return nil, nil, fmt.Errorf("launching firecracker: %w", err)
	}
	fail := func(err error) (vm.Instance, vsock.Agent, error) {
		killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = inst.Kill(killCtx)
		_ = m.net.Teardown(context.Background(), ns, meta.Slot)
		return nil, nil, fmt.Errorf("%w: %s", err, vm.LogTail(filepath.Join(sb.root, vm.LogFileName), 2048))
	}
	api := inst.API()
	if err := api.LoadSnapshot(ctx, firecracker.SnapshotLoadParams{
		SnapshotPath: inst.GuestPath(firecracker.SnapshotPath),
		MemBackend:   firecracker.MemoryBackend{BackendType: "File", BackendPath: inst.GuestPath(firecracker.MemPath)},
		ResumeVM:     true,
	}); err != nil {
		return fail(err)
	}
	if beforeAgent != nil {
		if err := beforeAgent(api, inst); err != nil {
			return fail(err)
		}
	}
	agent := m.agent(inst.VsockPath())
	if _, err := vsock.WaitReady(ctx, agent, m.cfg.BootTimeout); err != nil {
		return fail(err)
	}
	if err := agent.SetTime(ctx, time.Now()); err != nil {
		return fail(fmt.Errorf("set_time: %w", err))
	}
	if err := agent.Configure(ctx, vsock.ConfigureRequest{Hostname: meta.Hostname, DNS: m.cfg.DNS, FormatWorkspace: formatWorkspace}); err != nil {
		return fail(fmt.Errorf("configure: %w", err))
	}
	if _, err := agent.Ping(ctx); err != nil {
		return fail(fmt.Errorf("ping: %w", err))
	}
	sb.mu.Lock()
	sb.epoch++
	epoch := sb.epoch
	sb.inst = inst
	sb.agent = agent
	sb.mu.Unlock()
	go m.watch(sb, inst, epoch)
	return inst, agent, nil
}

// watch turns an unexpected Firecracker exit into the error state.
func (m *Manager) watch(sb *Sandbox, inst vm.Instance, epoch uint64) {
	<-inst.Done()
	sb.mu.Lock()
	if sb.epoch != epoch {
		sb.mu.Unlock()
		return
	}
	reason := "firecracker exited"
	if err := inst.ExitError(); err != nil {
		reason = fmt.Sprintf("firecracker exited: %v", err)
	}
	sb.inst = nil
	sb.agent = nil
	sb.meta.State = protocol.StateError
	sb.meta.Error = reason
	meta := sb.meta
	_ = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	m.log.Error("sandbox died", "sandbox", meta.ID, "reason", reason, "log", vm.LogTail(filepath.Join(sb.root, vm.LogFileName), 1024))
	_ = m.net.Teardown(context.Background(), m.namespace(meta.ID), meta.Slot)
	m.refreshGauges()
	m.events(protocol.Event{Type: protocol.FrameEvent, Event: protocol.EventSandboxDied, SandboxID: meta.ID, Reason: reason})
}

// detach invalidates the current instance so watch ignores its exit, and
// returns it for the caller to kill.
func (sb *Sandbox) detach() vm.Instance {
	sb.mu.Lock()
	defer sb.mu.Unlock()
	inst := sb.inst
	sb.inst = nil
	sb.agent = nil
	sb.epoch++
	return inst
}

// discard removes a failed create: process, netns, jail dir, slot,
// registry entry. Caller holds opMu.
func (m *Manager) discard(sb *Sandbox) {
	if inst := sb.detach(); inst != nil {
		killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		_ = inst.Kill(killCtx)
		cancel()
	}
	sb.mu.Lock()
	meta := sb.meta
	sb.mu.Unlock()
	_ = m.net.Teardown(context.Background(), m.namespace(meta.ID), meta.Slot)
	_ = os.RemoveAll(vm.JailDir(m.cfg.JailBase, meta.ID))
	if meta.Slot >= 0 {
		m.slots.Release(meta.Slot)
	}
	m.mu.Lock()
	if m.sandboxes[meta.ID] == sb {
		delete(m.sandboxes, meta.ID)
	}
	m.mu.Unlock()
	m.refreshGauges()
}

func (m *Manager) Resume(ctx context.Context, id string) (res protocol.ResumeResult, err error) {
	start := time.Now()
	defer func() {
		m.metrics.observe(protocol.OpResume, err)
		if err == nil && m.metrics != nil {
			m.metrics.Resume.Observe(time.Since(start).Seconds())
		}
	}()
	sb, err := m.get(id)
	if err != nil {
		return res, err
	}
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	sb.mu.Lock()
	state := sb.meta.State
	sb.mu.Unlock()
	if state != protocol.StatePaused {
		return res, fmt.Errorf("%w: %s is %s", ErrNotPaused, id, state)
	}
	for _, name := range []string{firecracker.MemPath, firecracker.SnapshotPath, firecracker.RootfsPath, firecracker.WorkspacePath, firecracker.KernelPath} {
		if !vm.Exists(filepath.Join(sb.root, name)) {
			return res, fmt.Errorf("sandbox %s is missing %s", id, name)
		}
	}
	log := m.log.With("sandbox", id)
	inst, _, err := m.restore(ctx, sb, log, nil, false)
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	sb.meta.State = protocol.StateRunning
	sb.meta.Error = ""
	err = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	if err != nil {
		return res, err
	}
	m.refreshGauges()
	log.Info("sandbox resumed", "restore", time.Since(start), "pid", inst.PID())
	return protocol.ResumeResult{RestoreMs: time.Since(start).Milliseconds()}, nil
}

func (m *Manager) Pause(ctx context.Context, id string) (res protocol.PauseResult, err error) {
	start := time.Now()
	defer func() {
		m.metrics.observe(protocol.OpPause, err)
		if err == nil && m.metrics != nil {
			m.metrics.Pause.Observe(time.Since(start).Seconds())
		}
	}()
	sb, err := m.get(id)
	if err != nil {
		return res, err
	}
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	sb.mu.Lock()
	inst := sb.inst
	state := sb.meta.State
	busy := sb.worker != nil || sb.inflight > 0
	sb.mu.Unlock()
	if state != protocol.StateRunning || inst == nil {
		return res, fmt.Errorf("%w: %s is %s", ErrNotRunning, id, state)
	}
	if busy {
		return res, fmt.Errorf("%w: %s", ErrBusy, id)
	}
	api := inst.API()
	if err := api.PatchVMState(ctx, firecracker.VMPaused); err != nil {
		return res, err
	}
	memNew := filepath.Join(sb.root, "mem.new")
	snapNew := filepath.Join(sb.root, "snapshot.new")
	if err := api.CreateSnapshot(ctx, firecracker.SnapshotCreateParams{
		SnapshotType: firecracker.SnapshotFull,
		SnapshotPath: inst.GuestPath("/snapshot.new"),
		MemFilePath:  inst.GuestPath("/mem.new"),
	}); err != nil {
		_ = os.Remove(memNew)
		_ = os.Remove(snapNew)
		resumeCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if resumeErr := api.PatchVMState(resumeCtx, firecracker.VMResumed); resumeErr != nil {
			return res, fmt.Errorf("snapshot failed (%v) and the vm could not be resumed: %w", err, resumeErr)
		}
		return res, fmt.Errorf("snapshot: %w", err)
	}
	sb.detach()
	killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := inst.Kill(killCtx); err != nil {
		return res, err
	}
	// The memory file the VM was mapped from must not change while it
	// runs; only now that the process is dead is it safe to replace.
	if err := vm.Rename(memNew, filepath.Join(sb.root, firecracker.MemPath)); err != nil {
		return res, err
	}
	if err := vm.Rename(snapNew, filepath.Join(sb.root, firecracker.SnapshotPath)); err != nil {
		return res, err
	}
	sb.mu.Lock()
	meta := sb.meta
	sb.mu.Unlock()
	if err := m.net.Teardown(context.Background(), m.namespace(id), meta.Slot); err != nil {
		m.log.Warn("network teardown", "sandbox", id, "error", err)
	}
	memBytes := vm.FileSize(filepath.Join(sb.root, firecracker.MemPath))
	sb.mu.Lock()
	sb.meta.State = protocol.StatePaused
	sb.meta.Generation++
	sb.meta.Error = ""
	err = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	if err != nil {
		return res, err
	}
	m.refreshGauges()
	m.log.Info("sandbox paused", "sandbox", id, "snapshot", time.Since(start), "mem_bytes", memBytes, "generation", meta.Generation+1)
	return protocol.PauseResult{SnapshotMs: time.Since(start).Milliseconds(), MemBytes: memBytes}, nil
}

func (m *Manager) Delete(ctx context.Context, id string) (err error) {
	defer func() { m.metrics.observe(protocol.OpDelete, err) }()
	sb, err := m.get(id)
	if err != nil {
		return err
	}
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	if inst := sb.detach(); inst != nil {
		killCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()
		if err := inst.Kill(killCtx); err != nil {
			return err
		}
	}
	sb.mu.Lock()
	meta := sb.meta
	sb.mu.Unlock()
	if err := m.net.Teardown(context.Background(), m.namespace(id), meta.Slot); err != nil {
		m.log.Warn("network teardown", "sandbox", id, "error", err)
	}
	if err := os.RemoveAll(vm.JailDir(m.cfg.JailBase, id)); err != nil {
		return err
	}
	if meta.Slot >= 0 {
		m.slots.Release(meta.Slot)
	}
	m.mu.Lock()
	delete(m.sandboxes, id)
	m.mu.Unlock()
	m.refreshGauges()
	m.log.Info("sandbox deleted", "sandbox", id)
	return nil
}

// acquireAgent marks an exec in flight and returns the agent.
func (m *Manager) acquireAgent(id string) (*Sandbox, vsock.Agent, error) {
	sb, err := m.get(id)
	if err != nil {
		return nil, nil, err
	}
	sb.mu.Lock()
	defer sb.mu.Unlock()
	if sb.meta.State != protocol.StateRunning || sb.agent == nil {
		return nil, nil, fmt.Errorf("%w: %s is %s", ErrNotRunning, id, sb.meta.State)
	}
	sb.inflight++
	return sb, sb.agent, nil
}

func (sb *Sandbox) releaseAgent() {
	sb.mu.Lock()
	sb.inflight--
	sb.mu.Unlock()
}

func (m *Manager) Exec(ctx context.Context, args protocol.ExecArgs, out vsock.OutputFunc) (res protocol.ExecResult, err error) {
	defer func() { m.metrics.observe(protocol.OpExec, err) }()
	if len(args.Cmd) == 0 {
		return res, errors.New("exec: cmd is empty")
	}
	sb, agent, err := m.acquireAgent(args.SandboxID)
	if err != nil {
		return res, err
	}
	defer sb.releaseAgent()
	if args.TimeoutMs > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, time.Duration(args.TimeoutMs)*time.Millisecond+10*time.Second)
		defer cancel()
	}
	cwd := args.Cwd
	if cwd == "" {
		cwd = guestWorkspace
	}
	start := time.Now()
	code, err := vsock.RunProcess(ctx, agent, vsock.ExecRequest{Cmd: args.Cmd, Env: args.Env, Cwd: cwd, TimeoutMs: args.TimeoutMs}, out)
	if err != nil {
		return res, err
	}
	return protocol.ExecResult{ExitCode: code, DurationMs: time.Since(start).Milliseconds()}, nil
}

func (m *Manager) StartWorker(ctx context.Context, args protocol.StartWorkerArgs) (res protocol.StartWorkerResult, err error) {
	defer func() { m.metrics.observe(protocol.OpStartWorker, err) }()
	sb, err := m.get(args.SandboxID)
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	if sb.meta.State != protocol.StateRunning || sb.agent == nil {
		state := sb.meta.State
		sb.mu.Unlock()
		return res, fmt.Errorf("%w: %s is %s", ErrNotRunning, args.SandboxID, state)
	}
	if sb.worker != nil {
		sb.mu.Unlock()
		return res, fmt.Errorf("%w: %s", ErrWorkerRunning, args.SandboxID)
	}
	agent := sb.agent
	// Reserve the worker slot before the handshake so two concurrent
	// start_worker commands cannot both start one.
	run := &workerRun{started: time.Now(), done: make(chan struct{})}
	sb.worker = run
	sb.mu.Unlock()

	log := m.log.With("sandbox", args.SandboxID, "process", "sbx-worker")
	logLines := newLineLogger(log)
	proc, err := agent.Start(ctx, vsock.ExecRequest{Cmd: []string{m.cfg.WorkerPath}, Env: args.Env, Cwd: guestWorkspace}, logLines.write)
	if err != nil {
		sb.mu.Lock()
		if sb.worker == run {
			sb.worker = nil
		}
		sb.mu.Unlock()
		close(run.done)
		return res, fmt.Errorf("starting worker: %w", err)
	}
	run.proc = proc
	if m.metrics != nil {
		m.metrics.Workers.Inc()
	}
	log.Info("worker started", "exec_id", proc.ID(), "env_keys", len(args.Env))
	go func() {
		code, waitErr := proc.Wait(context.Background())
		logLines.flush()
		duration := time.Since(run.started)
		sb.mu.Lock()
		if sb.worker == run {
			sb.worker = nil
		}
		sb.mu.Unlock()
		close(run.done)
		if m.metrics != nil {
			m.metrics.Workers.Dec()
		}
		event := protocol.Event{Type: protocol.FrameEvent, Event: protocol.EventWorkerExited, SandboxID: args.SandboxID, ExitCode: &code, DurationMs: duration.Milliseconds()}
		if waitErr != nil {
			event.Reason = waitErr.Error()
			log.Warn("worker ended abnormally", "error", waitErr, "duration", duration)
		} else {
			log.Info("worker exited", "exit_code", code, "duration", duration)
		}
		m.events(event)
	}()
	return protocol.StartWorkerResult{ExecID: proc.ID()}, nil
}

func (m *Manager) StopWorker(ctx context.Context, id string) (err error) {
	defer func() { m.metrics.observe(protocol.OpStopWorker, err) }()
	sb, err := m.get(id)
	if err != nil {
		return err
	}
	sb.mu.Lock()
	run := sb.worker
	sb.mu.Unlock()
	if run == nil || run.proc == nil {
		return fmt.Errorf("%w: %s", ErrNoWorker, id)
	}
	if err := run.proc.Signal(ctx, 15); err != nil {
		select {
		case <-run.done:
			return nil
		default:
			return fmt.Errorf("signalling worker: %w", err)
		}
	}
	select {
	case <-run.done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(m.cfg.StopWorkerGrace):
	}
	m.log.Warn("worker ignored SIGTERM, killing", "sandbox", id)
	if err := run.proc.Signal(ctx, 9); err != nil {
		return fmt.Errorf("killing worker: %w", err)
	}
	select {
	case <-run.done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(10 * time.Second):
		return errors.New("worker did not exit after SIGKILL")
	}
}

func (m *Manager) Status(ctx context.Context, id string) (protocol.SandboxInfo, error) {
	sb, err := m.get(id)
	if err != nil {
		return protocol.SandboxInfo{}, err
	}
	return sb.info(), nil
}

func (sb *Sandbox) info() protocol.SandboxInfo {
	sb.mu.Lock()
	defer sb.mu.Unlock()
	return sb.meta.Info(sb.worker != nil)
}

func (m *Manager) List() []protocol.SandboxInfo {
	m.mu.Lock()
	all := make([]*Sandbox, 0, len(m.sandboxes))
	for _, sb := range m.sandboxes {
		all = append(all, sb)
	}
	m.mu.Unlock()
	infos := make([]protocol.SandboxInfo, 0, len(all))
	for _, sb := range all {
		infos = append(infos, sb.info())
	}
	sort.Slice(infos, func(i, j int) bool { return infos[i].ID < infos[j].ID })
	return infos
}

func (m *Manager) Templates() []protocol.TemplateInfo {
	templates, err := m.store.List()
	if err != nil {
		m.log.Warn("listing templates", "error", err)
	}
	infos := make([]protocol.TemplateInfo, 0, len(templates))
	for _, t := range templates {
		shapes := []string{}
		for _, s := range t.ReadyShapes() {
			shapes = append(shapes, s.String())
		}
		infos = append(infos, protocol.TemplateInfo{Name: t.Name, Tag: t.Tag, Ready: true, Shapes: shapes})
	}
	return infos
}

// BuildTemplate builds a shape snapshot on demand (admin API, prebuild).
func (m *Manager) BuildTemplate(ctx context.Context, name, tag string, shape template.Shape) error {
	tmpl, err := m.store.Resolve(name, tag)
	if err != nil {
		return err
	}
	_, err = m.builder.Ensure(ctx, tmpl, shape)
	return err
}

func (m *Manager) refreshGauges() {
	if m.metrics == nil {
		return
	}
	counts := map[string]int{protocol.StateRunning: 0, protocol.StatePaused: 0, protocol.StateError: 0, "creating": 0}
	m.mu.Lock()
	for _, sb := range m.sandboxes {
		sb.mu.Lock()
		counts[sb.meta.State]++
		sb.mu.Unlock()
	}
	m.mu.Unlock()
	for state, n := range counts {
		m.metrics.Sandboxes.WithLabelValues(state).Set(float64(n))
	}
}

// Recover rebuilds the registry from the jail directories after a restart.
// Nothing survives a pod restart, so a sandbox recorded as running is
// downgraded to paused when its snapshot files exist and to error
// otherwise. Directories without metadata (a create or template build the
// restart interrupted) are removed, as are stale namespaces.
func (m *Manager) Recover(ctx context.Context) error {
	base := filepath.Join(m.cfg.JailBase, "firecracker")
	entries, err := os.ReadDir(base)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(base, e.Name())
		root := filepath.Join(dir, "root")
		meta, err := LoadMetadata(root)
		if err != nil {
			m.log.Warn("removing jail directory without metadata", "dir", dir, "error", err)
			if rmErr := os.RemoveAll(dir); rmErr != nil {
				return rmErr
			}
			continue
		}
		if meta.ID != e.Name() {
			m.log.Warn("removing jail directory whose metadata id does not match", "dir", dir, "id", meta.ID)
			_ = os.RemoveAll(dir)
			continue
		}
		for _, stale := range []string{"mem.new", "snapshot.new"} {
			_ = os.Remove(filepath.Join(root, stale))
		}
		if meta.Slot >= 0 {
			if err := m.slots.Reserve(meta.Slot); err != nil {
				meta.State = protocol.StateError
				meta.Error = fmt.Sprintf("slot %d: %v", meta.Slot, err)
			}
		}
		hasSnapshot := vm.Exists(filepath.Join(root, firecracker.MemPath)) && vm.Exists(filepath.Join(root, firecracker.SnapshotPath))
		switch meta.State {
		case protocol.StatePaused, protocol.StateError:
		default:
			if hasSnapshot {
				m.log.Warn("sandbox was running when the daemon stopped; treating its last snapshot as its state", "sandbox", meta.ID, "generation", meta.Generation)
				meta.State = protocol.StatePaused
				meta.Error = ""
			} else {
				meta.State = protocol.StateError
				meta.Error = "daemon restarted while running and no snapshot exists"
			}
		}
		if err := meta.Save(root); err != nil {
			return err
		}
		sb := &Sandbox{root: root, meta: meta}
		m.mu.Lock()
		m.sandboxes[meta.ID] = sb
		m.mu.Unlock()
		m.log.Info("recovered sandbox", "sandbox", meta.ID, "state", meta.State, "slot", meta.Slot)
	}
	namespaces, err := m.net.Namespaces(ctx)
	if err != nil {
		m.log.Warn("listing network namespaces", "error", err)
	}
	for _, ns := range namespaces {
		if !strings.HasPrefix(ns, "sbx-") {
			continue
		}
		if err := m.net.Teardown(ctx, ns, -1); err != nil {
			m.log.Warn("tearing down stale namespace", "netns", ns, "error", err)
		}
	}
	m.refreshGauges()
	return nil
}

// Shutdown pauses every running sandbox without a worker, concurrently,
// until ctx expires.
func (m *Manager) Shutdown(ctx context.Context) {
	var wg sync.WaitGroup
	for _, info := range m.List() {
		if info.State != protocol.StateRunning || info.WorkerRunning {
			continue
		}
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			if _, err := m.Pause(ctx, id); err != nil {
				m.log.Error("pausing sandbox on shutdown", "sandbox", id, "error", err)
			}
		}(info.ID)
	}
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-ctx.Done():
		m.log.Warn("shutdown deadline reached with pauses still in flight")
	}
}

// lineLogger writes guest stdout/stderr to the daemon log one line at a
// time.
type lineLogger struct {
	mu   sync.Mutex
	log  *slog.Logger
	bufs map[string][]byte
}

func newLineLogger(log *slog.Logger) *lineLogger {
	return &lineLogger{log: log, bufs: map[string][]byte{}}
}

func (l *lineLogger) write(stream string, data []byte) {
	l.mu.Lock()
	defer l.mu.Unlock()
	buf := append(l.bufs[stream], data...)
	for {
		idx := -1
		for i, b := range buf {
			if b == '\n' {
				idx = i
				break
			}
		}
		if idx < 0 {
			break
		}
		l.log.Info("guest output", "stream", stream, "line", string(buf[:idx]))
		buf = buf[idx+1:]
	}
	if len(buf) > 64*1024 {
		l.log.Info("guest output", "stream", stream, "line", string(buf))
		buf = nil
	}
	l.bufs[stream] = buf
}

func (l *lineLogger) flush() {
	l.mu.Lock()
	defer l.mu.Unlock()
	for stream, buf := range l.bufs {
		if len(buf) > 0 {
			l.log.Info("guest output", "stream", stream, "line", string(buf))
		}
		delete(l.bufs, stream)
	}
}
