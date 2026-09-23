package template

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/network"
	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

const (
	DefaultWorkspaceGB = 10
	DefaultBootTimeout = 2 * time.Minute
	// TemplateHostname is the hostname baked into the snapshot; configure
	// replaces it in every sandbox.
	TemplateHostname = "sandbox"
)

// Builder boots a template with a shape and snapshots it. Builds are
// serialized per (template, shape); concurrent Ensure calls wait for the
// running build.
type Builder struct {
	Store              *Store
	Launcher           vm.Launcher
	Network            network.Interface
	Slots              *network.Slots
	Agent              func(vsockPath string) vsock.Agent
	JailBase           string
	FirecrackerBin     string
	JailerBin          string
	JailerEnabled      bool
	UIDBase            int
	DNS                []string
	FirecrackerVersion string
	WorkspaceGB        int
	BootTimeout        time.Duration
	Log                *slog.Logger
	Events             func(protocol.Event)
	// Observe receives the duration and outcome of every build.
	Observe func(shape Shape, elapsed time.Duration, err error)

	mu     sync.Mutex
	builds map[string]*build
}

type build struct {
	done chan struct{}
	err  error
}

var idSanitizer = regexp.MustCompile(`[^A-Za-z0-9-]+`)

// BuildID is the jailer id of a template build.
func BuildID(t Template, shape Shape) string {
	id := idSanitizer.ReplaceAllString(fmt.Sprintf("tmpl-%s-%s-%s", t.Name, t.Tag, shape), "-")
	if len(id) > 64 {
		id = id[:64]
	}
	return strings.TrimRight(id, "-")
}

// Ensure returns the shape's artifacts, building the snapshot first if it
// does not exist. The build runs detached from ctx so that a caller giving
// up does not abort a build other callers wait on.
func (b *Builder) Ensure(ctx context.Context, t Template, shape Shape) (Artifacts, error) {
	if err := shape.Validate(); err != nil {
		return Artifacts{}, err
	}
	if t.ShapeReady(shape) {
		return t.Artifacts(shape)
	}
	key := t.Name + "/" + t.Tag + "/" + shape.String()
	b.mu.Lock()
	if b.builds == nil {
		b.builds = map[string]*build{}
	}
	bld, running := b.builds[key]
	if !running {
		bld = &build{done: make(chan struct{})}
		b.builds[key] = bld
		go b.run(t, shape, key, bld)
	}
	b.mu.Unlock()
	select {
	case <-bld.done:
	case <-ctx.Done():
		return Artifacts{}, ctx.Err()
	}
	if bld.err != nil {
		return Artifacts{}, bld.err
	}
	return t.Artifacts(shape)
}

func (b *Builder) run(t Template, shape Shape, key string, bld *build) {
	timeout := b.BootTimeout
	if timeout == 0 {
		timeout = DefaultBootTimeout
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout+5*time.Minute)
	defer cancel()
	start := time.Now()
	err := b.build(ctx, t, shape)
	if b.Observe != nil {
		b.Observe(shape, time.Since(start), err)
	}
	log := b.logger().With("template", t.Name, "tag", t.Tag, "shape", shape.String())
	if err != nil {
		log.Error("template build failed", "error", err, "elapsed", time.Since(start))
	} else {
		log.Info("template ready", "elapsed", time.Since(start))
		if b.Events != nil {
			b.Events(protocol.Event{Type: protocol.FrameEvent, Event: protocol.EventTemplateReady, Name: t.Name, Tag: t.Tag, Shape: shape.String()})
		}
	}
	bld.err = err
	b.mu.Lock()
	delete(b.builds, key)
	b.mu.Unlock()
	close(bld.done)
}

func (b *Builder) logger() *slog.Logger {
	if b.Log != nil {
		return b.Log
	}
	return slog.Default()
}

func (b *Builder) build(ctx context.Context, t Template, shape Shape) (err error) {
	id := BuildID(t, shape)
	log := b.logger().With("build", id)
	slot, err := b.Slots.Allocate()
	if err != nil {
		return err
	}
	defer b.Slots.Release(slot)
	uid := b.UIDBase + slot
	ns := network.BuildNamespaceName(id)
	jailDir := vm.JailDir(b.JailBase, id)
	root := vm.RootDir(b.JailBase, id)
	if err := os.RemoveAll(jailDir); err != nil {
		return err
	}
	defer func() {
		if rmErr := os.RemoveAll(jailDir); rmErr != nil && err == nil {
			err = rmErr
		}
	}()
	if err := vm.Prepare(root, uid, uid); err != nil {
		return err
	}
	workspaceGB := b.WorkspaceGB
	if workspaceGB <= 0 {
		workspaceGB = DefaultWorkspaceGB
	}
	if err := vm.HardLink(t.Kernel(), filepath.Join(root, firecracker.KernelPath)); err != nil {
		return err
	}
	rootfs := filepath.Join(root, firecracker.RootfsPath)
	if err := vm.Reflink(t.Rootfs(), rootfs); err != nil {
		return err
	}
	if err := vm.Chown(rootfs, uid, uid); err != nil {
		return err
	}
	workspace := filepath.Join(root, firecracker.WorkspacePath)
	if err := vm.Sparse(workspace, int64(workspaceGB)<<30); err != nil {
		return err
	}
	if err := vm.Chown(workspace, uid, uid); err != nil {
		return err
	}

	if err := b.Network.Setup(ctx, ns, slot); err != nil {
		return fmt.Errorf("network setup: %w", err)
	}
	defer func() {
		if tdErr := b.Network.Teardown(context.Background(), ns, slot); tdErr != nil {
			log.Warn("network teardown", "error", tdErr)
		}
	}()

	inst, err := b.Launcher.Launch(ctx, vm.Spec{
		ID: id, JailBase: b.JailBase, FirecrackerBin: b.FirecrackerBin, JailerBin: b.JailerBin,
		JailerEnabled: b.JailerEnabled, UID: uid, GID: uid, NetNS: ns,
	})
	if err != nil {
		return fmt.Errorf("launching firecracker: %w", err)
	}
	defer func() {
		killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if killErr := inst.Kill(killCtx); killErr != nil {
			log.Warn("killing template vm", "error", killErr)
		}
	}()

	api := inst.API()
	steps := []struct {
		name string
		fn   func() error
	}{
		{"machine-config", func() error {
			return api.PutMachineConfig(ctx, firecracker.MachineConfig{VCPUCount: shape.VCPUs, MemSizeMiB: shape.MemoryMB, SMT: false, TrackDirtyPages: false})
		}},
		{"boot-source", func() error {
			return api.PutBootSource(ctx, firecracker.BootSource{KernelImagePath: inst.GuestPath(firecracker.KernelPath), BootArgs: firecracker.BootArgs(b.DNS, TemplateHostname)})
		}},
		{"rootfs drive", func() error {
			return api.PutDrive(ctx, firecracker.Drive{DriveID: firecracker.RootDriveID, PathOnHost: inst.GuestPath(firecracker.RootfsPath), IsRootDevice: true})
		}},
		{"workspace drive", func() error {
			return api.PutDrive(ctx, firecracker.Drive{DriveID: firecracker.WorkspaceDriveID, PathOnHost: inst.GuestPath(firecracker.WorkspacePath)})
		}},
		{"network-interface", func() error {
			return api.PutNetworkInterface(ctx, firecracker.NetworkInterface{IfaceID: firecracker.IfaceID, GuestMAC: firecracker.GuestMAC, HostDevName: firecracker.TapName})
		}},
		{"vsock", func() error {
			return api.PutVsock(ctx, firecracker.Vsock{GuestCID: firecracker.GuestCID, UDSPath: inst.GuestPath(firecracker.VsockPath)})
		}},
		{"instance start", func() error { return api.InstanceStart(ctx) }},
	}
	for _, step := range steps {
		if err := step.fn(); err != nil {
			return fmt.Errorf("%s: %w: %s", step.name, err, vm.LogTail(filepath.Join(root, vm.LogFileName), 2048))
		}
	}
	bootStart := time.Now()
	agent := b.Agent(inst.VsockPath())
	pong, err := vsock.WaitReady(ctx, agent, b.bootTimeout())
	if err != nil {
		return fmt.Errorf("waiting for guest agent: %w: %s", err, vm.LogTail(filepath.Join(root, vm.LogFileName), 4096))
	}
	log.Info("template guest booted", "boot", time.Since(bootStart), "agent_version", pong.AgentVersion)

	if err := api.PatchVMState(ctx, firecracker.VMPaused); err != nil {
		return err
	}
	snapStart := time.Now()
	if err := api.CreateSnapshot(ctx, firecracker.SnapshotCreateParams{
		SnapshotType: firecracker.SnapshotFull,
		SnapshotPath: inst.GuestPath(firecracker.SnapshotPath),
		MemFilePath:  inst.GuestPath(firecracker.MemPath),
	}); err != nil {
		return err
	}
	// The template VM is never resumed: the snapshot is only valid together
	// with the disk exactly as it was at this moment.
	killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := inst.Kill(killCtx); err != nil {
		return err
	}
	log.Info("template snapshot taken", "snapshot", time.Since(snapStart), "mem_bytes", vm.FileSize(filepath.Join(root, firecracker.MemPath)))

	final := t.ShapeDir(shape)
	staging := final + buildSuffix
	if err := os.RemoveAll(staging); err != nil {
		return err
	}
	if err := os.MkdirAll(staging, 0o755); err != nil {
		return err
	}
	moves := []struct{ src, dst string }{
		{rootfs, filepath.Join(staging, BootRootfs)},
		{filepath.Join(root, firecracker.MemPath), filepath.Join(staging, MemFile)},
		{filepath.Join(root, firecracker.SnapshotPath), filepath.Join(staging, SnapshotFile)},
	}
	for _, mv := range moves {
		if err := vm.Rename(mv.src, mv.dst); err != nil {
			return fmt.Errorf("moving %s: %w", mv.src, err)
		}
		// Sandboxes of any jail uid read these (hard links and reflink
		// sources), so they must stay world-readable.
		if err := os.Chmod(mv.dst, 0o644); err != nil {
			return err
		}
	}
	meta := Metadata{
		Name: t.Name, Tag: t.Tag, Kernel: t.seedKernel(), VCPUs: shape.VCPUs, MemoryMB: shape.MemoryMB,
		WorkspaceGB: workspaceGB, FirecrackerVersion: b.FirecrackerVersion, BuiltAt: time.Now().UTC(),
	}
	if err := writeJSON(filepath.Join(staging, MetadataFile), meta); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(staging, ReadyFile), []byte(meta.BuiltAt.Format(time.RFC3339)+"\n"), 0o644); err != nil {
		return err
	}
	if err := os.RemoveAll(final); err != nil {
		return err
	}
	if err := os.Rename(staging, final); err != nil {
		return err
	}
	return nil
}

func (b *Builder) bootTimeout() time.Duration {
	if b.BootTimeout > 0 {
		return b.BootTimeout
	}
	return DefaultBootTimeout
}

func writeJSON(path string, v any) error {
	data, err := jsonMarshalIndent(v)
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

var ErrNoTemplates = errors.New("no templates found")
