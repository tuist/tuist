// Package sandbox is the node-side sandbox lifecycle: create from a template
// snapshot, pause to disk, resume, delete, exec and the worker process. One
// registry entry per sandbox with an on-disk metadata.json in its jail root.
package sandbox

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/blobcache"
	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/hostinfo"
	"github.com/tuist/tuist/infra/sandboxd/internal/lazydisk"
	"github.com/tuist/tuist/infra/sandboxd/internal/network"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
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
	// DefaultTemplateTag is the tag creates use for the default template
	// when the caller names none, so older template versions left on disk
	// never make the default ambiguous. SetDefaultTemplateTag moves it when
	// the installer completes a newer tag.
	DefaultTemplateTag string
	BootTimeout        time.Duration
	WorkerPath         string
	StopWorkerGrace    time.Duration
	// AllowedShapes, when set, is the only set of shapes Create accepts.
	// Every new shape costs a template build and a memory image on disk,
	// so nodes only offer the shapes they are sized for.
	AllowedShapes []template.Shape
	// SnapshotDir holds disk snapshots; empty disables them.
	SnapshotDir string
	// CacheImageDir holds ext4 cache images that creates may attach as an
	// extra drive; empty disables cache drives.
	CacheImageDir string
	// CacheImagesBytes bounds the masters copied into CacheImageDir for
	// cache grants; zero refuses grants.
	CacheImagesBytes int64
	// CacheImagesTTL removes a copied master unused for this long, so one of
	// a cleared volume or a deleted account does not linger on the node.
	CacheImagesTTL time.Duration
	// FirecrackerVersion is the running binary's version, recorded with
	// every memory image a pause writes.
	FirecrackerVersion string
	// SnapshotCompat is the node's hostinfo.SnapshotCompat. Archives carry
	// memory only when it is set, and restore it warm only where it matches.
	SnapshotCompat string
	// DiffSnapshots restores VMs from their local memory image with KVM
	// dirty-page tracking, and pauses such a VM with a Diff snapshot merged
	// into a reflink of that image, so a pause writes what the guest changed
	// since its restore rather than all of its memory.
	DiffSnapshots bool
}

type Deps struct {
	Store    *template.Store
	Builder  *template.Builder
	Launcher vm.Launcher
	Network  network.Interface
	Slots    *network.Slots
	Agent    func(vsockPath string) vsock.Agent
	// CloneFile defaults to vm.Reflink; fake-VM tests can copy their tiny fixtures.
	CloneFile func(src, dst string) error
	// HTTPClient moves archives to and from object storage.
	HTTPClient *http.Client
	Metrics    *Metrics
	// Blobs, when set, serves execution guests large input blobs from the
	// node; see serveBlobs.
	Blobs *blobcache.Cache
	// Checkouts, when set, is the node's runner-cache agent: a worker whose
	// start_worker carries a checkout grant is served the repository's master
	// and exports back to it; see armCheckout.
	Checkouts      checkout.Agent
	CheckoutLimits checkout.Limits
	// Workspaces, when set with Checkouts, keeps prepared workspaces built
	// from seeds, which a fresh sandbox's first worker starts from; see
	// preparedWorkspace.
	Workspaces *checkout.Workspaces
	// Cgroups, when set, spawns each VM into its own cgroup weighted by its
	// guaranteed CPU (hostinfo.VMCgroups).
	Cgroups *hostinfo.VMCgroups
	Events  func(protocol.Event)
	Log     *slog.Logger

	// CacheImages copies granted runner-cache masters onto the node: the
	// node's runner-cache agent. Nil refuses cache grants.
	CacheImages CacheImageSource
}

type Manager struct {
	cfg       Config
	store     *template.Store
	builder   *template.Builder
	launcher  vm.Launcher
	net       network.Interface
	slots     *network.Slots
	agent     func(string) vsock.Agent
	cloneFile func(string, string) error
	http      *http.Client
	metrics   *Metrics
	events    func(protocol.Event)
	log       *slog.Logger
	claims    *Claims
	blobs     *blobcache.Cache
	// checkouts and checkoutLimits serve workers' checkout grants.
	checkouts      checkout.Agent
	cacheImages    cacheImages
	checkoutLimits checkout.Limits
	workspaces     *checkout.Workspaces
	cgroups        *hostinfo.VMCgroups

	// defaultTag is the current DefaultTemplateTag.
	defaultTag atomic.Pointer[string]

	mu        sync.Mutex
	sandboxes map[string]*Sandbox
	// snapMu serializes changes to the disk snapshot directory with the
	// clones read from it.
	snapMu sync.Mutex
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
	// pausing is set, together with the busy check, for the whole of a
	// pause, so no exec or worker can start against a VM that is being
	// snapshotted.
	pausing bool
	// epoch changes on every spawn and deliberate kill so a death watcher
	// can tell whether the process it saw exit is still the current one.
	epoch uint64
	// resumes counts resumes and deletes asked for, and cancelArchive stops
	// an archive in flight, so a sandbox the server wants back never waits
	// out an upload.
	resumes       uint64
	cancelArchive context.CancelFunc
	// fresh is set on a sandbox created from the template snapshot until its
	// first exec or worker: its workspace is the empty disk the create
	// formatted, which a prepared workspace may replace.
	fresh bool
	// inputsSwapped is set once an execution VM got its scope's inputs
	// image as its workspace; see inputsWorkspace.
	inputsSwapped bool
	// memoryPending is set while a warm restore still reads memory from
	// its archive, disksPending while it still reads its disks (lazy, until
	// then); EventMemoryLoaded reports both cleared.
	memoryPending bool
	disksPending  bool
	lazy          *lazyDisks
	// memoryLoading is closed once a warm restore's memory is all on the
	// node; set only while that restore waits for its guest agent.
	memoryLoading chan struct{}
	// memoryServed is the instance whose guest memory this process serves
	// through userfaultfd: a warm restore's, until its memory is all on the
	// node and released (uffd.Options.Release). It cannot outlive the
	// daemon until then.
	memoryServed vm.Instance
}

var (
	ErrNotFound      = errors.New("sandbox not found")
	ErrAlreadyExists = errors.New("sandbox already exists")
	ErrNotRunning    = errors.New("sandbox is not running")
	ErrNotPaused     = errors.New("sandbox is not paused")
	ErrBusy          = errors.New("sandbox has a worker or exec running")
	ErrPausing       = errors.New("sandbox is being paused")
	ErrShape         = errors.New("shape is not offered by this node")
	ErrNoWorker      = errors.New("no worker running")
	ErrWorkerRunning = errors.New("worker already running")
	// ErrVMNotKilled marks a failed spawn whose Firecracker did not die
	// when killed: it may still hold, and write, the sandbox's disks.
	ErrVMNotKilled = errors.New("firecracker did not die")
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
	if deps.CloneFile == nil {
		deps.CloneFile = vm.Reflink
	}
	if deps.HTTPClient == nil {
		deps.HTTPClient = defaultHTTPClient()
	}
	m := &Manager{
		cfg: cfg, store: deps.Store, builder: deps.Builder, launcher: deps.Launcher, net: deps.Network,
		slots: deps.Slots, agent: deps.Agent, metrics: deps.Metrics, events: deps.Events, log: deps.Log,
		cloneFile: deps.CloneFile,
		http:      deps.HTTPClient,
		blobs:     deps.Blobs,
		checkouts: deps.Checkouts, checkoutLimits: deps.CheckoutLimits, workspaces: deps.Workspaces, cacheImages: cacheImages{source: deps.CacheImages},
		cgroups:   deps.Cgroups,
		sandboxes: map[string]*Sandbox{},
		claims:    NewClaims(),
	}
	m.SetDefaultTemplateTag(cfg.DefaultTemplateTag)
	return m
}

// DefaultTemplateTag is the tag creates of the default template use when
// the caller names none.
func (m *Manager) DefaultTemplateTag() string { return *m.defaultTag.Load() }

// SetDefaultTemplateTag makes creates that name no tag use tag from now on.
// Sandboxes already created keep the tag they were created from.
func (m *Manager) SetDefaultTemplateTag(tag string) { m.defaultTag.Store(&tag) }

// Claims holds the claimed execs waiting for their direct caller.
func (m *Manager) Claims() *Claims { return m.claims }

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
	if args.ExpiresAtUnix != 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithDeadline(ctx, time.Unix(args.ExpiresAtUnix, 0))
		defer cancel()
		if err := ctx.Err(); err != nil {
			return res, err
		}
	}
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
	if !m.shapeAllowed(shape) {
		return res, fmt.Errorf("%w: %s", ErrShape, shape)
	}
	if args.WorkspaceGB <= 0 {
		args.WorkspaceGB = DefaultWorkspaceGB
	}
	if args.Hostname == "" {
		args.Hostname = m.namespace(args.SandboxID)
	}
	// A disk snapshot or an archive carries its own kernel and disks, so it
	// needs neither the template on disk nor its shape snapshot.
	fromSnapshot := args.FromDiskSnapshot != ""
	fromArchive := args.FromArchive != nil
	if fromSnapshot && fromArchive {
		return res, errors.New("create takes a disk snapshot or an archive, not both")
	}
	if args.CacheGrant != nil {
		if args.CacheImage != "" {
			return res, fmt.Errorf("%w: a create takes a cache image or a cache grant, not both", ErrCacheImage)
		}
		// Assigns the named err, which the deferred report below reads.
		var name string
		var generation int64
		var release func()
		name, generation, release, err = m.grantedCacheImage(ctx, *args.CacheGrant)
		if err != nil {
			return res, err
		}
		defer release()
		// Whether the image was copied now or reused, this names the cache a
		// sandbox's disks received.
		m.log.Info("cache image granted to sandbox", "sandbox", args.SandboxID, "image", name, "scope", args.CacheGrant.Scope, "generation", generation, "granted_generation", args.CacheGrant.BaseGeneration)
		defer func() {
			if err == nil {
				res.CacheGeneration = generation
			}
		}()
		args.CacheImage = name
	}
	if args.CacheImage != "" {
		if m.cfg.CacheImageDir == "" {
			return res, fmt.Errorf("%w: this daemon has no cache image directory", ErrCacheImage)
		}
		// An archive without a memory image always cold boots, like a disk
		// snapshot, so it can take a cache drive; one with memory restores
		// a guest that never had it.
		if fromArchive && args.FromArchive.TailOffset > 0 {
			return res, fmt.Errorf("%w: a create from an archive with memory cannot attach one", ErrCacheImage)
		}
		if err := vm.ValidateID(args.CacheImage); err != nil {
			return res, fmt.Errorf("%w: %v", ErrCacheImage, err)
		}
	}
	var tmpl template.Template
	if fromSnapshot || fromArchive {
		if fromSnapshot {
			if err := vm.ValidateID(args.FromDiskSnapshot); err != nil {
				return res, err
			}
		}
		tmpl.Name = args.Template
		if tmpl.Name == "" {
			tmpl.Name = m.cfg.DefaultTemplate
		}
	} else {
		var err error
		if tmpl, err = m.resolveTemplate(args.Template, args.TemplateTag); err != nil {
			return res, err
		}
	}
	log := m.log.With("sandbox", args.SandboxID)

	root := vm.RootDir(m.cfg.JailBase, args.SandboxID)
	sb := &Sandbox{root: root, meta: Metadata{
		ID: args.SandboxID, Template: tmpl.Name, Tag: tmpl.Tag, VCPUs: shape.VCPUs, MemoryMB: shape.MemoryMB,
		WorkspaceGB: args.WorkspaceGB, Hostname: args.Hostname, CPUGuaranteeMilli: args.CPUGuaranteeMilli,
		State: "creating", Slot: -1, CreatedAt: time.Now().UTC(),
	}}
	m.mu.Lock()
	// Check under the same lock that publishes the new sandbox. After the
	// lease expires, delete either sees this in-flight create and waits on
	// opMu, or no later replay can insert it behind the deletion.
	if err := ctx.Err(); err != nil {
		m.mu.Unlock()
		return res, err
	}
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

	if fromSnapshot {
		return m.createFromDiskSnapshot(ctx, sb, args, log)
	}
	if fromArchive {
		return m.createFromArchive(ctx, sb, args, log)
	}
	artifacts, err := m.builder.Ensure(ctx, tmpl, shape)
	if err != nil {
		return res, fmt.Errorf("template %s/%s %s: %w", tmpl.Name, tmpl.Tag, shape, err)
	}
	if args.CacheImage != "" && !artifacts.Meta.CacheDrive {
		return res, fmt.Errorf("%w: template %s/%s %s has no cache drive to swap one into", ErrCacheImage, tmpl.Name, tmpl.Tag, shape)
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
	if err := m.cloneFile(artifacts.Rootfs, rootfs); err != nil {
		return res, err
	}
	if err := vm.Chown(rootfs, uid, uid); err != nil {
		return res, err
	}
	workspace := filepath.Join(root, firecracker.WorkspacePath)
	preparedWorkspace := artifacts.Meta.WorkspacePrepared && args.WorkspaceGB == artifacts.Meta.WorkspaceGB
	if preparedWorkspace {
		if err := m.cloneFile(artifacts.Workspace, workspace); err != nil {
			return res, err
		}
	} else {
		if err := vm.Sparse(workspace, int64(args.WorkspaceGB)<<30); err != nil {
			return res, err
		}
	}
	if err := vm.Chown(workspace, uid, uid); err != nil {
		return res, err
	}
	// The snapshot opens its placeholder cache drive on restore, so the jail
	// needs one; a requested cache image takes its place.
	if artifacts.Meta.CacheDrive {
		if args.CacheImage != "" {
			err = m.attachCacheImage(args.CacheImage, root, uid)
			sb.mu.Lock()
			sb.meta.CacheImage = args.CacheImage
			sb.mu.Unlock()
		} else {
			err = m.cachePlaceholder(root, uid)
		}
		if err != nil {
			return res, err
		}
	}

	bootStart := time.Now()
	inst, agent, err := m.restore(ctx, sb, log, func(api *firecracker.Client, inst vm.Instance) error {
		// The guest cached each drive's capacity at template boot; a drive
		// patch makes Firecracker re-read the file size and notify the
		// guest. The guest must drop its buffers for /dev/vdc before it
		// mounts a cache, since it may have read the placeholder's blocks.
		if args.CacheImage != "" {
			if err := api.PatchDrive(ctx, firecracker.DrivePatch{DriveID: firecracker.CacheDriveID, PathOnHost: inst.GuestPath(firecracker.CachePath)}); err != nil {
				return fmt.Errorf("swapping in cache drive: %w", err)
			}
		}
		if args.WorkspaceGB == artifacts.Meta.WorkspaceGB {
			return nil
		}
		return api.PatchDrive(ctx, firecracker.DrivePatch{DriveID: firecracker.WorkspaceDriveID, PathOnHost: inst.GuestPath(firecracker.WorkspacePath)})
	}, !preparedWorkspace)
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	sb.meta.State = protocol.StateRunning
	sb.meta.Generation = 0
	sb.meta.FirecrackerVersion = artifacts.Meta.FirecrackerVersion
	sb.meta.Error = ""
	sb.fresh = !preparedWorkspace
	err = sb.meta.Save(root)
	sb.mu.Unlock()
	if err != nil {
		return res, err
	}
	m.refreshGauges()
	log.Info("sandbox created", "template", tmpl.Name, "tag", tmpl.Tag, "shape", shape.String(), "slot", slot, "boot", time.Since(bootStart), "pid", inst.PID(), "agent", agent != nil)
	return protocol.CreateResult{BootMs: time.Since(bootStart).Milliseconds()}, nil
}

// resolveTemplate applies the daemon's defaults to a caller's template
// choice: an empty name is the default template, and an empty tag on the
// default template is the configured tag rather than "whatever single
// version is on disk", which stops being unique after a template upgrade.
func (m *Manager) resolveTemplate(name, tag string) (template.Template, error) {
	if name == "" {
		name = m.cfg.DefaultTemplate
	}
	if tag == "" && name == m.cfg.DefaultTemplate {
		tag = m.DefaultTemplateTag()
	}
	return m.store.Resolve(name, tag)
}

// spawn sets up the sandbox's network namespace and starts a Firecracker
// process for it. The returned fail func tears both down again and decorates
// the error with the tail of the Firecracker log.
func (m *Manager) spawn(ctx context.Context, sb *Sandbox, meta Metadata) (vm.Instance, func(error) (vm.Instance, vsock.Agent, error), error) {
	networkStarted := time.Now()
	ns := m.namespace(meta.ID)
	if err := m.net.Setup(ctx, ns, meta.Slot); err != nil {
		return nil, nil, fmt.Errorf("network setup: %w", err)
	}
	m.observePhase("network_setup", networkStarted)
	launchStarted := time.Now()
	spec := m.vmSpec(meta)
	if m.cgroups != nil {
		guarantee := meta.CPUGuaranteeMilli
		if guarantee == 0 {
			guarantee = protocol.DefaultCPUGuaranteeMilli
		}
		// Without its own cgroup the VM still runs, in the daemon's, as
		// before guarantees: it then shares the daemon's weight.
		// The shape's guest memory is the VM's request: the container's
		// limit reclaims from the daemon's page cache before it.
		if cgroup, err := m.cgroups.Open(meta.ID, guarantee, uint64(meta.MemoryMB)<<20); err != nil { //nolint:gosec // Shapes are positive.
			m.log.Warn("opening the sandbox's cgroup failed; it runs in the daemon's", "sandbox", meta.ID, "error", err)
		} else {
			defer cgroup.Close()
			spec.Cgroup = cgroup
		}
	}
	inst, err := m.launcher.Launch(ctx, spec)
	if err != nil {
		_ = m.net.Teardown(context.Background(), ns, meta.Slot)
		return nil, nil, fmt.Errorf("launching firecracker: %w", err)
	}
	m.observePhase("launch", launchStarted)
	fail := func(err error) (vm.Instance, vsock.Agent, error) {
		killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if killErr := inst.Kill(killCtx); killErr != nil {
			err = fmt.Errorf("%w; %w: %w", err, ErrVMNotKilled, killErr)
		}
		_ = m.net.Teardown(context.Background(), ns, meta.Slot)
		// The console log carries guest output, so it stays in the daemon's
		// log rather than travelling to the server inside the error.
		m.log.Warn("sandbox spawn failed", "sandbox", meta.ID, "error", err, "log", vm.LogTail(filepath.Join(sb.root, vm.LogFileName), 2048))
		return nil, nil, err
	}
	return inst, fail, nil
}

// waitReady gives the guest agent BootTimeout to answer. A warm archive
// restore's guest runs on memory it faults in from the archive, which can
// take most of that, so its BootTimeout starts once the memory is all on the
// node, or once the deadline leaves only room for a full BootTimeout and a
// cold boot after it.
func (m *Manager) waitReady(ctx context.Context, sb *Sandbox, agent vsock.Agent, observe func(vsock.PingAttempt)) error {
	sb.mu.Lock()
	loading := sb.memoryLoading
	sb.mu.Unlock()
	start := time.Now()
	if loading != nil {
		const unbounded = 24 * time.Hour
		deadline := start.Add(unbounded)
		if d, ok := ctx.Deadline(); ok {
			deadline = d.Add(-2 * m.cfg.BootTimeout)
		}
		waitCtx, cancel := context.WithDeadline(ctx, deadline)
		go func() {
			select {
			case <-loading:
				cancel()
			case <-waitCtx.Done():
			}
		}()
		// waitCtx ends this wait, never its own timeout.
		_, err := vsock.WaitReadyObserved(waitCtx, agent, unbounded, observe)
		cancel()
		if err == nil || ctx.Err() != nil {
			return err
		}
	}
	offset := time.Since(start)
	_, err := vsock.WaitReadyObserved(ctx, agent, m.cfg.BootTimeout, func(p vsock.PingAttempt) {
		p.At += offset
		observe(p)
	})
	return err
}

func (m *Manager) vmSpec(meta Metadata) vm.Spec {
	uid := m.cfg.UIDBase + meta.Slot
	return vm.Spec{
		ID: meta.ID, JailBase: m.cfg.JailBase, FirecrackerBin: m.cfg.FirecrackerBin, JailerBin: m.cfg.JailerBin,
		JailerEnabled: m.cfg.JailerEnabled, UID: uid, GID: uid, NetNS: m.namespace(meta.ID),
	}
}

// attach brings the guest agent up to date after a restore or a boot (clock,
// hostname, DNS, workspace) and starts watching the process.
func (m *Manager) attach(ctx context.Context, sb *Sandbox, inst vm.Instance, meta Metadata, formatWorkspace bool, fail func(error) (vm.Instance, vsock.Agent, error)) (vm.Instance, vsock.Agent, error) {
	started := time.Now()
	agent := m.agent(inst.VsockPath())
	readiness := newReadinessLog()
	err := m.waitReady(ctx, sb, agent, readiness.add)
	readiness.report(m.log, meta.ID, time.Since(started), err)
	if err != nil {
		return fail(err)
	}
	if err := agent.SetTime(ctx, time.Now()); err != nil {
		return fail(fmt.Errorf("set_time: %w", err))
	}
	m.observePhase("agent_ready", started)
	started = time.Now()
	if err := agent.Configure(ctx, vsock.ConfigureRequest{Hostname: meta.Hostname, DNS: m.cfg.DNS, FormatWorkspace: formatWorkspace}); err != nil {
		return fail(fmt.Errorf("configure: %w", err))
	}
	m.observePhase("guest_configure", started)
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

// restore spawns Firecracker for sb, loads /snapshot + /mem with resume and
// brings the guest agent up to date. beforeAgent runs after the load and
// before the agent handshake.
func (m *Manager) restore(ctx context.Context, sb *Sandbox, log *slog.Logger, beforeAgent func(*firecracker.Client, vm.Instance) error, formatWorkspace bool) (vm.Instance, vsock.Agent, error) {
	return m.restoreWith(ctx, sb, log, "", beforeAgent, formatWorkspace)
}

// restoreWith is restore with the memory served through the userfaultfd
// socket at memSocket in the jail instead of /mem, when it is set.
func (m *Manager) restoreWith(ctx context.Context, sb *Sandbox, log *slog.Logger, memSocket string, beforeAgent func(*firecracker.Client, vm.Instance) error, formatWorkspace bool) (vm.Instance, vsock.Agent, error) {
	sb.mu.Lock()
	meta := sb.meta
	sb.mu.Unlock()
	inst, fail, err := m.spawn(ctx, sb, meta)
	if err != nil {
		return nil, nil, err
	}
	api := inst.API()
	loadStarted := time.Now()
	backend := firecracker.MemoryBackend{BackendType: "File", BackendPath: inst.GuestPath(firecracker.MemPath)}
	if memSocket != "" {
		backend = firecracker.MemoryBackend{BackendType: "Uffd", BackendPath: inst.GuestPath(memSocket)}
	}
	// Only a VM mapped from the jail's own memory file has a base a Diff
	// can be merged onto; one served through userfaultfd has none on disk.
	tracked := m.cfg.DiffSnapshots && memSocket == ""
	if err := api.LoadSnapshot(ctx, firecracker.SnapshotLoadParams{
		SnapshotPath:    inst.GuestPath(firecracker.SnapshotPath),
		MemBackend:      backend,
		ResumeVM:        true,
		TrackDirtyPages: tracked,
	}); err != nil {
		return fail(err)
	}
	sb.mu.Lock()
	sb.meta.MemoryTracked = tracked
	sb.mu.Unlock()
	m.observePhase("load_snapshot", loadStarted)
	if beforeAgent != nil {
		if err := beforeAgent(api, inst); err != nil {
			return fail(err)
		}
	}
	return m.attach(ctx, sb, inst, meta, formatWorkspace, fail)
}

// boot starts the sandbox from its kernel and its own disks without any
// memory image: the cold path for a sandbox whose last snapshot no longer
// matches its disks. For the guest it is a power cut: processes are gone,
// flushed data survives with its journals replayed on mount, and writes
// still in its page cache are lost.
func (m *Manager) boot(ctx context.Context, sb *Sandbox, log *slog.Logger) (vm.Instance, vsock.Agent, error) {
	sb.mu.Lock()
	// A booted guest has no memory image under it to merge a Diff onto.
	sb.meta.MemoryTracked = false
	meta := sb.meta
	sb.mu.Unlock()
	inst, fail, err := m.spawn(ctx, sb, meta)
	if err != nil {
		return nil, nil, err
	}
	api := inst.API()
	steps := []struct {
		name string
		fn   func() error
	}{
		{"machine-config", func() error {
			return api.PutMachineConfig(ctx, firecracker.MachineConfig{VCPUCount: meta.VCPUs, MemSizeMiB: meta.MemoryMB, SMT: false, TrackDirtyPages: false})
		}},
		{"boot-source", func() error {
			return api.PutBootSource(ctx, firecracker.BootSource{KernelImagePath: inst.GuestPath(firecracker.KernelPath), BootArgs: firecracker.BootArgs(m.cfg.DNS, meta.Hostname)})
		}},
		{"rootfs drive", func() error {
			return api.PutDrive(ctx, firecracker.Drive{DriveID: firecracker.RootDriveID, PathOnHost: inst.GuestPath(firecracker.RootfsPath), IsRootDevice: true})
		}},
		{"workspace drive", func() error {
			return api.PutDrive(ctx, firecracker.Drive{DriveID: firecracker.WorkspaceDriveID, PathOnHost: inst.GuestPath(firecracker.WorkspacePath)})
		}},
		// A cold reboot keeps the cache drive the sandbox was created with.
		{"cache drive", func() error {
			if !vm.Exists(filepath.Join(sb.root, firecracker.CachePath)) {
				return nil
			}
			return api.PutDrive(ctx, firecracker.Drive{DriveID: firecracker.CacheDriveID, PathOnHost: inst.GuestPath(firecracker.CachePath)})
		}},
		{"network-interface", func() error {
			return api.PutNetworkInterface(ctx, firecracker.NetworkInterface{IfaceID: firecracker.IfaceID, GuestMAC: firecracker.GuestMAC, HostDevName: firecracker.TapName})
		}},
		{"vsock", func() error {
			return api.PutVsock(ctx, firecracker.Vsock{GuestCID: firecracker.GuestCID, UDSPath: inst.GuestPath(firecracker.VsockPath)})
		}},
		// A cold boot gets the balloon shape snapshots get, so the sandbox
		// returns free memory from here on whatever it was created from.
		{"balloon", func() error {
			if m.builder == nil || !m.builder.Balloon {
				return nil
			}
			return api.PutBalloon(ctx, firecracker.ReportingBalloon)
		}},
		{"instance start", func() error { return api.InstanceStart(ctx) }},
	}
	for _, step := range steps {
		if err := step.fn(); err != nil {
			return fail(fmt.Errorf("%s: %w", step.name, err))
		}
	}
	log.Info("sandbox cold booting on its own disks", "generation", meta.Generation)
	return m.attach(ctx, sb, inst, meta, false, fail)
}

// releaseCgroup removes the cgroup of a VM whose process is gone. The page
// cache it is still charged for (the memory image a pause wrote, its disk
// I/O) moves to the container's cgroup, out of the VM's memory.low, so the
// reclaim before a carve-out shrink can drop it. The next spawn opens a
// fresh cgroup.
func (m *Manager) releaseCgroup(id string) {
	if m.cgroups == nil {
		return
	}
	if err := m.cgroups.Remove(id); err != nil {
		m.log.Warn("removing the sandbox's cgroup failed", "sandbox", id, "error", err)
	}
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
	sb.dropAgent()
	sb.meta.State = protocol.StateError
	sb.meta.Error = reason
	meta := sb.meta
	_ = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	m.log.Error("sandbox died", "sandbox", meta.ID, "reason", reason, "log", vm.LogTail(filepath.Join(sb.root, vm.LogFileName), 1024))
	m.releaseCgroup(meta.ID)
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
	sb.dropAgent()
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
	m.releaseCgroup(meta.ID)
	_ = m.net.Teardown(context.Background(), m.namespace(meta.ID), meta.Slot)
	m.dropLazyDisks(sb)
	_ = os.RemoveAll(vm.JailDir(m.cfg.JailBase, meta.ID))
	if meta.Slot >= 0 {
		m.slots.Release(meta.Slot)
		sb.mu.Lock()
		sb.meta.Slot = -1
		sb.mu.Unlock()
	}
	m.mu.Lock()
	if m.sandboxes[meta.ID] == sb {
		delete(m.sandboxes, meta.ID)
	}
	m.mu.Unlock()
	m.refreshGauges()
}

// current reports whether sb is still the registry entry for id. A caller
// that waited on opMu re-checks it: the entry may have been discarded or
// deleted, and its slot handed to another sandbox, in the meantime.
func (m *Manager) current(id string, sb *Sandbox) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.sandboxes[id] == sb
}

func (m *Manager) shapeAllowed(shape template.Shape) bool {
	if len(m.cfg.AllowedShapes) == 0 {
		return true
	}
	for _, allowed := range m.cfg.AllowedShapes {
		if allowed == shape {
			return true
		}
	}
	return false
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
	sb.interruptArchive()
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	if !m.current(id, sb) {
		return res, fmt.Errorf("%w: %s", ErrNotFound, id)
	}
	sb.mu.Lock()
	state := sb.meta.State
	running := state == protocol.StateRunning && sb.inst != nil
	sb.mu.Unlock()
	// A resume whose answer the server never saw is retried; the sandbox
	// it asks for is already up, which is what the caller wants.
	if running {
		return protocol.ResumeResult{}, nil
	}
	if state != protocol.StatePaused {
		return res, fmt.Errorf("%w: %s is %s", ErrNotPaused, id, state)
	}
	sb.mu.Lock()
	coldBoot := sb.meta.ColdBoot
	sb.mu.Unlock()
	required := []string{firecracker.RootfsPath, firecracker.WorkspacePath, firecracker.KernelPath}
	if !coldBoot {
		required = append(required, firecracker.MemPath, firecracker.SnapshotPath)
	}
	for _, name := range required {
		if !vm.Exists(filepath.Join(sb.root, name)) {
			return res, fmt.Errorf("sandbox %s is missing %s", id, name)
		}
	}
	log := m.log.With("sandbox", id)
	var inst vm.Instance
	var agent vsock.Agent
	if coldBoot {
		inst, agent, err = m.boot(ctx, sb, log)
	} else {
		loaded := false
		inst, agent, err = m.restore(ctx, sb, log, func(*firecracker.Client, vm.Instance) error {
			loaded = true
			return nil
		}, false)
		if err != nil && loaded && errors.Is(err, ErrVMNotKilled) {
			// The guest ran and its process may still write the disks, so
			// neither they nor the image can be trusted, as in PauseWith.
			// A second VM on them would corrupt them.
			m.markDied(sb, fmt.Sprintf("resume: %v", err))
			return res, err
		}
		if err != nil && loaded {
			// The guest ran from the image before the restore failed, as one
			// snapshotted while it hung does when its agent never answers,
			// and was killed, so its disks have moved on past the image.
			// Restoring the image again would fail the same way or hand the
			// guest a stale page cache: cold boot on the disks instead, and
			// record it first so a boot that fails too is not retried
			// from the image.
			log.Warn("restoring the sandbox's memory failed after the guest resumed; cold booting on its own disks", "error", err)
			sb.mu.Lock()
			sb.meta.ColdBoot = true
			sb.meta.DisksSynced = false
			saveErr := sb.meta.Save(sb.root)
			sb.mu.Unlock()
			if saveErr != nil {
				return res, errors.Join(err, saveErr)
			}
			coldBoot = true
			inst, agent, err = m.boot(ctx, sb, log)
		}
	}
	if err != nil {
		return res, err
	}
	m.growRootfs(ctx, sb, inst, agent, log)
	if coldBoot {
		// The old memory image can never be valid again; the next pause
		// writes a fresh pair.
		for _, stale := range []string{firecracker.MemPath, firecracker.SnapshotPath} {
			_ = os.Remove(filepath.Join(sb.root, stale))
		}
	}
	sb.mu.Lock()
	sb.meta.State = protocol.StateRunning
	sb.meta.ColdBoot = false
	sb.meta.DisksSynced = false
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

func (m *Manager) Pause(ctx context.Context, id string) (protocol.PauseResult, error) {
	return m.PauseWith(ctx, protocol.PauseArgs{SandboxID: id})
}

// PauseWith snapshots the VM's memory and stops it. With SyncDisks it first
// flushes the guest's page cache, so the disks alone hold everything that
// was written and SaveDisks may copy them; a failed sync still pauses, but
// leaves the disks marked unsynced.
func (m *Manager) PauseWith(ctx context.Context, args protocol.PauseArgs) (res protocol.PauseResult, err error) {
	id := args.SandboxID
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
	if err := m.awaitLazyDisks(ctx, id, sb); err != nil {
		return res, err
	}
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	if !m.current(id, sb) {
		return res, fmt.Errorf("%w: %s", ErrNotFound, id)
	}
	sb.mu.Lock()
	inst := sb.inst
	state := sb.meta.State
	busy := sb.worker != nil || sb.inflight > 0
	if state == protocol.StateRunning && inst != nil && !busy {
		sb.pausing = true
	}
	sb.mu.Unlock()
	if state != protocol.StateRunning || inst == nil {
		return res, fmt.Errorf("%w: %s is %s", ErrNotRunning, id, state)
	}
	if busy {
		return res, fmt.Errorf("%w: %s", ErrBusy, id)
	}
	defer func() {
		sb.mu.Lock()
		sb.pausing = false
		sb.mu.Unlock()
	}()
	synced, syncFailed := false, false
	if args.SyncDisks {
		if err := m.syncGuest(ctx, sb); err != nil {
			m.log.Warn("guest sync before pause failed; the disks will not be saved", "sandbox", id, "error", err)
			syncFailed = true
		} else {
			synced = true
		}
	}
	// A ballooned guest returns the cache it drops, so the snapshot stores
	// zeros (punched below) instead of cache the guest rereads from disk.
	// A guest whose sync just timed out would only time out again, which
	// would push the pause past the server's 120 s call.
	if m.builder != nil && m.builder.Balloon && !syncFailed {
		dropStart := time.Now()
		if cached, err := m.dropGuestCache(ctx, sb); err != nil {
			m.log.Warn("dropping the guest's page cache before pause failed", "sandbox", id, "error", err)
		} else if cached > 64<<20 {
			awaitReturnedMemory(ctx, inst, 5*time.Second)
			m.log.Info("dropped the guest's page cache before pause", "sandbox", id, "cached_bytes", cached, "duration", time.Since(dropStart))
		}
	}
	api := inst.API()
	if err := api.PatchVMState(ctx, firecracker.VMPaused); err != nil {
		return res, err
	}
	// The guest's CPU time up to its pause, read before the snapshot's own
	// work adds to the process's, so the server bills the time since the
	// VM's last report.
	var cpuMs int64
	if cpu, ok := inst.CPUTime(); ok {
		cpuMs = cpu.Milliseconds()
	}
	// Its memory too, before writing the snapshot reads every guest page.
	mem, _ := inst.ResidentMemory()
	memNew := filepath.Join(sb.root, "mem.new")
	snapNew := filepath.Join(sb.root, "snapshot.new")
	snapshotType := m.snapshotBase(sb, memNew)
	writeStart := time.Now()
	if err := api.CreateSnapshot(ctx, firecracker.SnapshotCreateParams{
		SnapshotType: snapshotType,
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
	written := time.Since(writeStart)
	sb.detach()
	killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := inst.Kill(killCtx); err != nil {
		// The process may still be writing to the disks, so neither image
		// can be trusted any more.
		m.markDied(sb, fmt.Sprintf("pause: firecracker did not die: %v", err))
		return res, err
	}
	m.releaseCgroup(id)
	// A guest that returns its free memory (the balloon) leaves those pages
	// zero in the image; free their blocks before it is installed so the
	// image uses disk for what the guest holds. Readers see the same bytes.
	if m.builder != nil && m.builder.Balloon {
		punchStart := time.Now()
		if punched, err := vm.PunchZeros(memNew); err != nil {
			m.log.Warn("punching the memory image's zero blocks failed", "sandbox", id, "error", err)
		} else {
			m.log.Info("punched the memory image's zero blocks", "sandbox", id, "punched_bytes", punched, "duration", time.Since(punchStart))
		}
	}
	// A restore whose disks still arrive from its archive holds them
	// whole only once the fill ends.
	if err := m.settleLazyDisks(context.Background(), sb); err != nil {
		m.markDied(sb, fmt.Sprintf("pause: the restored disks could not be completed: %v", err))
		return res, err
	}
	sb.mu.Lock()
	meta := sb.meta
	sb.mu.Unlock()
	if err := m.net.Teardown(context.Background(), m.namespace(id), meta.Slot); err != nil {
		m.log.Warn("network teardown", "sandbox", id, "error", err)
	}
	// The memory file the VM was mapped from must not change while it
	// runs; only now that the process is dead is it safe to replace. The
	// two renames are not atomic together: if either fails the pair may be
	// mismatched, but the VM is dead and its disks are consistent, so the
	// sandbox stays usable through a cold boot.
	if err := m.installSnapshot(sb, memNew, snapNew); err != nil {
		m.log.Warn("installing snapshot failed; the sandbox will cold boot", "sandbox", id, "error", err)
		sb.mu.Lock()
		sb.meta.State = protocol.StatePaused
		sb.meta.ColdBoot = true
		sb.meta.DisksSynced = synced
		sb.meta.PausedCPUMs = cpuMs
		sb.meta.Error = ""
		saveErr := sb.meta.Save(sb.root)
		sb.mu.Unlock()
		m.refreshGauges()
		if saveErr != nil {
			return res, saveErr
		}
		return protocol.PauseResult{SnapshotMs: time.Since(start).Milliseconds(), DisksSynced: synced, CPUMs: cpuMs, MemoryAnonBytes: mem.AnonBytes, MemoryFileBytes: mem.FileBytes}, nil
	}
	memBytes := vm.FileSize(filepath.Join(sb.root, firecracker.MemPath))
	sb.mu.Lock()
	// The snapshot read every page, so a warm restore's memory is all on
	// the node now, and its disks were settled above.
	memoryLoaded := sb.memoryPending || sb.disksPending
	sb.memoryPending, sb.disksPending = false, false
	sb.meta.State = protocol.StatePaused
	sb.meta.MemoryTracked = false
	sb.meta.Generation++
	sb.meta.FirecrackerVersion = m.cfg.FirecrackerVersion
	sb.meta.DisksSynced = synced
	sb.meta.PausedCPUMs = cpuMs
	sb.meta.Error = ""
	err = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	if err != nil {
		return res, err
	}
	m.refreshGauges()
	if memoryLoaded {
		m.events(protocol.Event{Type: protocol.FrameEvent, Event: protocol.EventMemoryLoaded, SandboxID: id})
	}
	m.log.Info("sandbox paused", "sandbox", id, "snapshot", time.Since(start), "mem_bytes", memBytes, "generation", meta.Generation+1, "snapshot_type", string(snapshotType), "snapshot_write", written)
	return protocol.PauseResult{SnapshotMs: time.Since(start).Milliseconds(), MemBytes: memBytes, DisksSynced: synced, CPUMs: cpuMs, MemoryAnonBytes: mem.AnonBytes, MemoryFileBytes: mem.FileBytes}, nil
}

// snapshotBase prepares memNew for the pause's snapshot and says which kind
// to take. A VM restored with dirty-page tracking from the jail's mem gets a
// reflink of that file, which Firecracker merges its Diff into (it merges
// into an existing memory file of the guest's size), so only the pages the
// guest changed since its restore are written. Anything else, or a clone
// that fails, takes a Full snapshot over a fresh file.
func (m *Manager) snapshotBase(sb *Sandbox, memNew string) firecracker.SnapshotType {
	sb.mu.Lock()
	tracked, slot, id := sb.meta.MemoryTracked, sb.meta.Slot, sb.meta.ID
	sb.mu.Unlock()
	_ = os.Remove(memNew)
	if !tracked {
		return firecracker.SnapshotFull
	}
	uid := m.cfg.UIDBase + slot
	err := m.cloneFile(filepath.Join(sb.root, firecracker.MemPath), memNew)
	if err == nil {
		// The base may be the template's root-owned memfile; the jailed
		// Firecracker writes the clone.
		err = os.Chmod(memNew, 0o600)
	}
	if err == nil {
		err = vm.Chown(memNew, uid, uid)
	}
	if err != nil {
		_ = os.Remove(memNew)
		m.log.Warn("cloning the memory image for a diff snapshot failed; taking a full one", "sandbox", id, "error", err)
		return firecracker.SnapshotFull
	}
	return firecracker.SnapshotDiff
}

func (m *Manager) Delete(ctx context.Context, id string) (err error) {
	defer func() { m.metrics.observe(protocol.OpDelete, err) }()
	if err := vm.ValidateID(id); err != nil {
		return err
	}
	sb, err := m.get(id)
	if errors.Is(err, ErrNotFound) {
		// Deleting what the node does not hold succeeds: the server may be
		// cleaning up after a lost create or a sandbox the node already
		// dropped. Remove anything left on disk under that id.
		_ = m.net.Teardown(context.Background(), m.namespace(id), -1)
		if err := os.RemoveAll(vm.JailDir(m.cfg.JailBase, id)); err != nil {
			return err
		}
		m.log.Info("delete of an unknown sandbox", "sandbox", id)
		return nil
	}
	if err != nil {
		return err
	}
	sb.interruptArchive()
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	if !m.current(id, sb) {
		// A concurrent delete or a failed create removed it while this
		// call waited, and released its slot.
		return nil
	}
	sb.mu.Lock()
	meta := sb.meta
	inst := sb.inst
	// Invalidate watch, but retain the instance until death is confirmed.
	// A failed kill must not make the next delete mistake a live VM for nil.
	sb.epoch++
	sb.dropAgent()
	sb.meta.State = protocol.StateError
	sb.meta.Error = "deletion pending"
	sb.mu.Unlock()
	cleanupCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	// Network removal and process exit are independent. Await both before
	// removing disks or releasing the slot; a used VM is never pooled.
	networkDone := make(chan error, 1)
	go func() {
		started := time.Now()
		err := m.net.Teardown(cleanupCtx, m.namespace(id), meta.Slot)
		m.observePhase("network_teardown", started)
		networkDone <- err
	}()
	started := time.Now()
	var killErr error
	if inst != nil {
		killErr = inst.Kill(cleanupCtx)
	}
	m.observePhase("kill", started)
	networkErr := <-networkDone
	if killErr != nil || networkErr != nil {
		return errors.Join(killErr, networkErr)
	}
	sb.mu.Lock()
	sb.inst = nil
	sb.mu.Unlock()
	m.dropLazyDisks(sb)
	m.releaseCgroup(id)
	started = time.Now()
	if err := os.RemoveAll(vm.JailDir(m.cfg.JailBase, id)); err != nil {
		return err
	}
	m.observePhase("remove_files", started)
	if meta.Slot >= 0 {
		m.slots.Release(meta.Slot)
		sb.mu.Lock()
		sb.meta.Slot = -1
		sb.mu.Unlock()
	}
	m.mu.Lock()
	if m.sandboxes[id] == sb {
		delete(m.sandboxes, id)
	}
	m.mu.Unlock()
	m.refreshGauges()
	m.log.Info("sandbox deleted", "sandbox", id)
	return nil
}

// installSnapshot moves a freshly written memory image and snapshot into
// place.
func (m *Manager) installSnapshot(sb *Sandbox, memNew, snapNew string) error {
	if err := vm.Rename(memNew, filepath.Join(sb.root, firecracker.MemPath)); err != nil {
		_ = os.Remove(memNew)
		_ = os.Remove(snapNew)
		return err
	}
	if err := vm.Rename(snapNew, filepath.Join(sb.root, firecracker.SnapshotPath)); err != nil {
		_ = os.Remove(snapNew)
		return err
	}
	return nil
}

// markDied moves a sandbox whose VM can no longer be trusted to the error
// state, as watch does for an unexpected exit, and tells the server.
func (m *Manager) markDied(sb *Sandbox, reason string) {
	sb.mu.Lock()
	sb.inst = nil
	sb.dropAgent()
	sb.meta.State = protocol.StateError
	sb.meta.Error = reason
	meta := sb.meta
	_ = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	m.log.Error("sandbox died", "sandbox", meta.ID, "reason", reason)
	_ = m.net.Teardown(context.Background(), m.namespace(meta.ID), meta.Slot)
	m.refreshGauges()
	m.events(protocol.Event{Type: protocol.FrameEvent, Event: protocol.EventSandboxDied, SandboxID: meta.ID, Reason: reason})
}

// dropAgent forgets the guest connection and closes a prewarmed one. The
// caller holds sb.mu.
func (sb *Sandbox) dropAgent() {
	if spare, ok := sb.agent.(interface{ CloseSpare() }); ok {
		spare.CloseSpare()
	}
	sb.agent = nil
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
	if sb.pausing {
		return nil, nil, fmt.Errorf("%w: %s", ErrPausing, id)
	}
	sb.inflight++
	sb.fresh = false
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
	m.inputsWorkspace(ctx, sb, agent, args)
	defer m.serveBlobs(sb, args)()
	if args.TimeoutMs > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, time.Duration(args.TimeoutMs)*time.Millisecond+10*time.Second)
		defer cancel()
	}
	cwd := args.Cwd
	if cwd == "" {
		cwd = guestWorkspace
	}
	if args.CPUGuaranteeMilli > 0 && m.cgroups != nil {
		// The VM runs at its old weight when this fails; the command still runs.
		if err := m.cgroups.Reweigh(sb.meta.ID, args.CPUGuaranteeMilli); err != nil {
			m.log.Warn("reweighing the sandbox's cgroup failed", "sandbox", sb.meta.ID, "error", err)
		}
	}
	start := time.Now()
	code, err := vsock.RunProcess(ctx, agent, vsock.ExecRequest{Cmd: args.Cmd, Env: args.Env, Cwd: cwd, TimeoutMs: args.TimeoutMs}, out)
	if err != nil {
		return res, err
	}
	// An execution VM's action follows its preparation, and the VM is never
	// paused in between: open the connection the action will use now.
	if prewarmer, ok := agent.(interface{ Prewarm(context.Context) }); ok && preparesExecution(args.Cmd) {
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			prewarmer.Prewarm(ctx)
		}()
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
	if sb.pausing {
		sb.mu.Unlock()
		return res, fmt.Errorf("%w: %s", ErrPausing, args.SandboxID)
	}
	if sb.worker != nil {
		sb.mu.Unlock()
		return res, fmt.Errorf("%w: %s", ErrWorkerRunning, args.SandboxID)
	}
	agent, inst := sb.agent, sb.inst
	// Reserve the worker slot before the handshake so two concurrent
	// start_worker commands cannot both start one.
	run := &workerRun{started: time.Now(), done: make(chan struct{})}
	sb.worker = run
	fresh := sb.fresh && sb.inflight == 0
	sb.fresh = false
	meta := sb.meta
	sb.mu.Unlock()

	log := m.log.With("sandbox", args.SandboxID, "process", "sbx-worker")
	logLines := newLineLogger(log)
	key, keyed := m.workspaceKey(meta, args.Checkout)
	prepared := keyed && fresh && m.preparedWorkspace(ctx, sb, inst, agent, key, log)
	// Served only while this worker runs: a pause waits for the worker, and
	// the exit below disarms before it frees the worker slot.
	env, disarm := m.armCheckout(inst, args, log, m.recorder(keyed && !prepared, key))
	proc, err := agent.Start(ctx, vsock.ExecRequest{Cmd: []string{m.cfg.WorkerPath}, Env: env, Cwd: guestWorkspace}, logLines.write)
	if err != nil {
		disarm()
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
		disarm()
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
		event := protocol.Event{Type: protocol.FrameEvent, Event: protocol.EventWorkerExited, SandboxID: args.SandboxID, WorkID: args.WorkID, ExitCode: &code, DurationMs: duration.Milliseconds()}
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
	return sb.info(m.cgroups), nil
}

func (sb *Sandbox) info(cgroups *hostinfo.VMCgroups) protocol.SandboxInfo {
	sb.mu.Lock()
	info := sb.meta.Info(sb.worker != nil)
	inst := sb.inst
	sb.mu.Unlock()
	if inst != nil && info.State == protocol.StateRunning {
		if cpu, ok := inst.CPUTime(); ok {
			info.CPUMs = cpu.Milliseconds()
		}
		if mem, ok := inst.ResidentMemory(); ok {
			info.MemoryAnonBytes, info.MemoryFileBytes = mem.AnonBytes, mem.FileBytes
		}
		if current, ok := cgroups.MemoryCurrent(info.ID); ok {
			info.MemoryCurrentBytes = current
		}
	}
	return info
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
		infos = append(infos, sb.info(m.cgroups))
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
		infos = append(infos, protocol.TemplateInfo{Name: t.Name, Tag: t.Tag, Ready: true, Shapes: shapes, RootfsBytes: vm.FileSize(t.Rootfs())})
	}
	return infos
}

// BuildTemplate builds a shape snapshot on demand (admin API, prebuild).
func (m *Manager) BuildTemplate(ctx context.Context, name, tag string, shape template.Shape) error {
	if !m.shapeAllowed(shape) {
		return fmt.Errorf("%w: %s", ErrShape, shape)
	}
	tmpl, err := m.resolveTemplate(name, tag)
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
// A sandbox recorded as running lost its VM, so it is downgraded to paused
// when its snapshot files exist and to error otherwise, unless the previous
// daemon handed it over and the vmm container still holds that very
// process: the daemon then attaches it and it stays running (step 2b).
// Directories without metadata (a create or template build the restart
// interrupted) are removed, as are stale namespaces and the VMs vmm holds
// that no sandbox claims.
func (m *Manager) Recover(ctx context.Context) error {
	m.removePartialDiskSnapshots()
	m.removePartialCacheImages()
	attacher, _ := m.launcher.(vm.Attacher)
	held := map[string]vm.VMMVM{}
	if attacher != nil {
		vms, err := attacher.List(ctx)
		if err != nil {
			m.log.Warn("listing the VMs vmm holds; handed-over sandboxes cold boot", "error", err)
		}
		for _, v := range vms {
			held[v.ID] = v
		}
	}
	var handedOver []*Sandbox
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
		hasDisks := vm.Exists(filepath.Join(root, firecracker.RootfsPath)) && vm.Exists(filepath.Join(root, firecracker.WorkspacePath)) && vm.Exists(filepath.Join(root, firecracker.KernelPath))
		for _, name := range lazyDiskNames {
			// A previous daemon's mount over a disk being restored.
			lazydisk.Unmount(filepath.Join(root, name))
			if vm.Exists(filepath.Join(root, name+lazyDiskSuffix)) {
				// Its disks were still arriving from its archive, which the
				// server restores again.
				meta.State = protocol.StateError
				meta.Error = "daemon restarted while the sandbox's disks were still loading from its archive"
			}
		}
		switch meta.State {
		case protocol.StatePaused:
			if !meta.ColdBoot && meta.FirecrackerVersion != m.cfg.FirecrackerVersion && hasDisks {
				m.log.Warn("sandbox memory image was written by another Firecracker version; it will cold boot on its next resume", "sandbox", meta.ID, "image_version", meta.FirecrackerVersion, "firecracker", m.cfg.FirecrackerVersion)
				meta.ColdBoot = true
			}
		case protocol.StateError:
		default:
			if h := meta.Handover; h != nil && hasDisks && meta.Error == "" {
				if v, ok := held[meta.ID]; ok && !v.Exited && v.PID == h.PID && v.Start == h.Start {
					sb := &Sandbox{root: root, meta: meta}
					m.mu.Lock()
					m.sandboxes[meta.ID] = sb
					m.mu.Unlock()
					handedOver = append(handedOver, sb)
					continue
				}
				m.log.Warn("the sandbox's handed-over VM is gone; it will cold boot on its next resume", "sandbox", meta.ID, "pid", h.PID)
			}
			meta.Handover = nil
			// The VM was running when the daemon stopped, so its disks have
			// moved on since whatever memory image is on disk; restoring that
			// image against them would hand the guest a stale page cache and
			// journal. The sandbox comes back with a cold boot instead.
			if hasDisks {
				m.log.Warn("sandbox was running when the daemon stopped; it will cold boot on its next resume", "sandbox", meta.ID, "generation", meta.Generation)
				meta.State = protocol.StatePaused
				meta.ColdBoot = true
				meta.Error = ""
				// Nothing read its CPU time as it stopped; an earlier
				// pause's reading would bill the wrong interval.
				meta.PausedCPUMs = 0
			} else {
				meta.State = protocol.StateError
				meta.Error = "daemon restarted while running and the sandbox disks are missing"
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
	adopted := map[string]bool{}
	for _, sb := range handedOver {
		if err := m.adopt(ctx, sb, attacher); err != nil {
			m.lostHandover(sb, err)
			continue
		}
		adopted[sb.meta.ID] = true
	}
	// A VM no sandbox claims (its metadata moved on, or its adoption
	// failed and killed it already) must not run on beside the sandbox's
	// next spawn.
	for id, v := range held {
		if adopted[id] || v.Exited {
			continue
		}
		if inst, err := attacher.Attach(ctx, vm.Spec{ID: id, JailBase: m.cfg.JailBase}, v.PID); err == nil {
			m.log.Warn("killing a VM vmm holds that no sandbox claims", "sandbox", id, "pid", v.PID)
			killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			_ = inst.Kill(killCtx)
			cancel()
		}
	}
	namespaces, err := m.net.Namespaces(ctx)
	if err != nil {
		m.log.Warn("listing network namespaces", "error", err)
	}
	for _, ns := range namespaces {
		if !strings.HasPrefix(ns, "sbx-") {
			continue
		}
		if id, ok := strings.CutPrefix(ns, "sbx-"); ok && adopted[id] {
			continue
		}
		if err := m.net.Teardown(ctx, ns, -1); err != nil {
			m.log.Warn("tearing down stale namespace", "netns", ns, "error", err)
		}
	}
	m.refreshGauges()
	return nil
}

// Shutdown pauses every running sandbox within the deadline so a daemon
// restart restores memory rather than cold booting. A running worker is
// stopped first: its SIGTERM handler force-stops the work item, and
// Anthropic re-queues the session on its next event. Sandboxes that cannot
// be paused in time stay running and are marked for a cold boot on
// recovery.
func (m *Manager) Shutdown(ctx context.Context) {
	m.stopAll(ctx, func(id string) {
		// Synced, so the paused sandbox can be archived or saved without its
		// memory image, like any other pause.
		if _, err := m.PauseWith(ctx, protocol.PauseArgs{SandboxID: id, SyncDisks: true}); err != nil {
			m.log.Error("pausing sandbox on shutdown", "sandbox", id, "error", err)
		}
	})
}

// stopAll stops each running sandbox's worker and then runs stop for it,
// concurrently, until ctx expires.
func (m *Manager) stopAll(ctx context.Context, stop func(id string)) {
	var wg sync.WaitGroup
	for _, info := range m.List() {
		if info.State != protocol.StateRunning {
			continue
		}
		wg.Add(1)
		go func(id string, workerRunning bool) {
			defer wg.Done()
			if workerRunning {
				if err := m.StopWorker(ctx, id); err != nil && !errors.Is(err, ErrNoWorker) {
					m.log.Error("stopping worker on shutdown", "sandbox", id, "error", err)
					return
				}
			}
			stop(id)
		}(info.ID, info.WorkerRunning)
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

// adopt attaches the VM the previous daemon handed over and rebuilds what
// this process holds for it: the Firecracker API, the guest agent, the
// network namespace's name and the exit watch. It checks the process is
// that sandbox's running VM first; on any failure the VM is killed.
func (m *Manager) adopt(ctx context.Context, sb *Sandbox, attacher vm.Attacher) error {
	meta := sb.meta
	inst, err := attacher.Attach(ctx, m.vmSpec(meta), meta.Handover.PID)
	if err != nil {
		return fmt.Errorf("attaching pid %d: %w", meta.Handover.PID, err)
	}
	fail := func(err error) error {
		killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = inst.Kill(killCtx)
		return err
	}
	if h, ok := inst.(vm.Handoff); ok && h.Start() != meta.Handover.Start {
		return fail(fmt.Errorf("pid %d started at %d, not %d", inst.PID(), h.Start(), meta.Handover.Start))
	}
	checkCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	info, err := inst.API().Info(checkCtx)
	if err != nil {
		return fail(fmt.Errorf("firecracker api: %w", err))
	}
	if info.ID != meta.ID || info.State != "Running" {
		return fail(fmt.Errorf("firecracker answers as %q in state %q", info.ID, info.State))
	}
	if err := m.net.Adopt(checkCtx, m.namespace(meta.ID), inst.PID()); err != nil {
		return fail(fmt.Errorf("naming the network namespace: %w", err))
	}
	agent := m.agent(inst.VsockPath())
	if _, err := agent.Ping(checkCtx); err != nil {
		return fail(fmt.Errorf("guest agent: %w", err))
	}
	sb.mu.Lock()
	sb.epoch++
	epoch := sb.epoch
	sb.inst, sb.agent = inst, agent
	sb.meta.Handover = nil
	err = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	go m.watch(sb, inst, epoch)
	if err != nil {
		m.log.Error("saving a re-attached sandbox's metadata", "sandbox", meta.ID, "error", err)
	}
	m.log.Info("sandbox re-attached", "sandbox", meta.ID, "pid", inst.PID(), "slot", meta.Slot)
	return nil
}

// lostHandover is recovery's cold-boot path for a handed-over sandbox whose
// VM could not be attached.
func (m *Manager) lostHandover(sb *Sandbox, cause error) {
	sb.mu.Lock()
	sb.meta.Handover = nil
	sb.meta.State = protocol.StatePaused
	sb.meta.ColdBoot = true
	sb.meta.PausedCPUMs = 0
	meta := sb.meta
	err := sb.meta.Save(sb.root)
	sb.mu.Unlock()
	m.log.Warn("re-attaching a handed-over sandbox failed; it will cold boot on its next resume", "sandbox", meta.ID, "error", cause)
	if err != nil {
		m.log.Error("saving the sandbox's metadata", "sandbox", meta.ID, "error", err)
	}
	m.releaseCgroup(meta.ID)
	_ = m.net.Teardown(context.Background(), m.namespace(meta.ID), meta.Slot)
}

// Handover is Shutdown for an in-place upgrade of the daemon's container
// (step 2b): each running sandbox stays running in the vmm container,
// recorded for the next daemon to attach, instead of pausing. Its running
// worker is stopped first, as on Shutdown, since the worker's exec stream
// ends with this process. So does the memory server of a warm restore and
// the lazy mounts of disks still arriving from an archive: a sandbox that
// depends on either, or that vmm will not keep, is paused as Shutdown
// pauses it.
func (m *Manager) Handover(ctx context.Context) {
	m.stopAll(ctx, func(id string) {
		if m.handOver(ctx, id) {
			return
		}
		if _, err := m.PauseWith(ctx, protocol.PauseArgs{SandboxID: id, SyncDisks: true}); err != nil {
			m.log.Error("pausing sandbox on shutdown", "sandbox", id, "error", err)
		}
	})
}

// HandoverBlocked counts the running sandboxes a handover would pause:
// those whose disks still arrive through the daemon's mounts (minutes after
// a restore) and those whose guest memory the daemon still serves (seconds
// to a minute after a warm restore from an archive).
func (m *Manager) HandoverBlocked() (lazyDisks, memoryServed int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, sb := range m.sandboxes {
		sb.mu.Lock()
		if sb.meta.State == protocol.StateRunning && sb.inst != nil {
			if sb.lazy != nil {
				lazyDisks++
			}
			if sb.memoryServed == sb.inst {
				memoryServed++
			}
		}
		sb.mu.Unlock()
	}
	return lazyDisks, memoryServed
}

// handOver detaches the sandbox's VM and records it, reporting whether
// nothing is left to do for it (handed over, or no longer running).
func (m *Manager) handOver(ctx context.Context, id string) bool {
	sb, err := m.get(id)
	if err != nil {
		return true
	}
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	if !m.current(id, sb) {
		return true
	}
	sb.mu.Lock()
	if sb.meta.State != protocol.StateRunning || sb.inst == nil {
		sb.mu.Unlock()
		return true
	}
	inst := sb.inst
	h, ok := inst.(vm.Handoff)
	if !ok || sb.lazy != nil || sb.memoryServed == inst {
		sb.mu.Unlock()
		return false
	}
	// The detach ends the instance on this side; watch must not take that
	// for the VM's death.
	sb.epoch++
	sb.mu.Unlock()
	if err := h.Detach(ctx); err != nil {
		m.log.Warn("vmm did not keep the sandbox; pausing it", "sandbox", id, "error", err)
		sb.mu.Lock()
		sb.epoch++
		epoch := sb.epoch
		sb.mu.Unlock()
		go m.watch(sb, inst, epoch)
		return false
	}
	sb.mu.Lock()
	sb.inst = nil
	sb.dropAgent()
	sb.meta.Handover = &Handover{PID: inst.PID(), Start: h.Start()}
	err = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	if err != nil {
		// The next daemon finds no record, cold boots the sandbox and kills
		// the VM vmm keeps.
		m.log.Error("recording the handed-over sandbox", "sandbox", id, "error", err)
		return true
	}
	m.log.Info("sandbox handed over to the next daemon", "sandbox", id, "pid", inst.PID())
	return true
}

// lineLogger writes guest stdout/stderr to the daemon log one line at a
// time. The guest is untrusted, so lines are cut at maxLineBytes and a run
// logs at most maxLoggedLines before it is silenced.
type lineLogger struct {
	mu         sync.Mutex
	log        *slog.Logger
	bufs       map[string][]byte
	lines      int
	suppressed bool
}

const (
	maxLineBytes   = 4 * 1024
	maxLoggedLines = 5000
)

func newLineLogger(log *slog.Logger) *lineLogger {
	return &lineLogger{log: log, bufs: map[string][]byte{}}
}

func (l *lineLogger) emit(stream string, line []byte) {
	if l.suppressed {
		return
	}
	if l.lines >= maxLoggedLines {
		l.suppressed = true
		l.log.Warn("guest output exceeded the logging limit; further lines are dropped", "lines", l.lines)
		return
	}
	l.lines++
	if len(line) > maxLineBytes {
		line = line[:maxLineBytes]
	}
	l.log.Info("guest output", "stream", stream, "line", string(line))
}

func (l *lineLogger) write(stream string, data []byte) {
	l.mu.Lock()
	defer l.mu.Unlock()
	buf := append(l.bufs[stream], data...)
	for {
		idx := bytes.IndexByte(buf, '\n')
		if idx < 0 {
			break
		}
		l.emit(stream, buf[:idx])
		buf = buf[idx+1:]
	}
	if len(buf) > maxLineBytes {
		l.emit(stream, buf)
		buf = nil
	}
	l.bufs[stream] = buf
}

func (l *lineLogger) flush() {
	l.mu.Lock()
	defer l.mu.Unlock()
	for stream, buf := range l.bufs {
		if len(buf) > 0 {
			l.emit(stream, buf)
		}
		delete(l.bufs, stream)
	}
}

// Phase names are fixed at call sites; sandbox IDs never become metric labels.
func (m *Manager) observePhase(phase string, started time.Time) {
	duration := time.Since(started)
	if m.metrics != nil {
		m.metrics.Phases.WithLabelValues(phase).Observe(duration.Seconds())
	}
	m.log.Debug("sandbox lifecycle phase", "phase", phase, "duration", duration)
}

func preparesExecution(cmd []string) bool {
	return len(cmd) == 3 && cmd[0] == "/usr/local/bin/sbx-executor" && cmd[1] == "--prepare-cas"
}
