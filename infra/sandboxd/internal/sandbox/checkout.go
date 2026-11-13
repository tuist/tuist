package sandbox

import (
	"context"
	"errors"
	"log/slog"
	"maps"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// armCheckout lets a worker's guest start from the node's master of its
// repository and export back to it, for as long as the worker runs: it
// listens on the checkout vsock port and returns the worker env that tells the
// guest so. Without a grant, an agent or the listener, the env is unchanged
// and the guest clones as it would otherwise. The returned function stops
// serving. A non-nil record keeps a copy of the seed for the node's prepared
// workspaces.
func (m *Manager) armCheckout(inst vm.Instance, args protocol.StartWorkerArgs, log *slog.Logger, record checkout.Recorder) (map[string]string, func()) {
	grant := args.Checkout
	if grant == nil {
		return args.Env, func() {}
	}
	if m.checkouts == nil {
		log.Info("checkout granted, but no checkout agent is configured on this node")
		return args.Env, func() {}
	}
	if grant.ID == "" || !filepath.IsAbs(grant.Path) || filepath.Clean(grant.Path) != grant.Path {
		log.Warn("ignoring an invalid checkout grant", "use", grant.ID, "path", grant.Path)
		return args.Env, func() {}
	}
	if inst == nil {
		return args.Env, func() {}
	}
	path := inst.VsockPath() + "_" + strconv.Itoa(checkout.GuestPort)
	listener, err := listenForVMM(path, inst.Root())
	if err != nil {
		log.Warn("serving the checkout to the guest", "use", grant.ID, "error", err)
		return args.Env, func() {}
	}
	env := maps.Clone(args.Env)
	if env == nil {
		env = map[string]string{}
	}
	env[protocol.CheckoutPathEnv] = grant.Path
	env[protocol.CheckoutCommitEnv] = grant.Commit
	env[protocol.CheckoutVsockEnv] = strconv.Itoa(checkout.GuestPort)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		checkout.Serve(ctx, listener, m.checkouts, *grant, m.checkoutLimits, log, record)
	}()
	return env, func() {
		cancel()
		<-done
		os.Remove(path)
	}
}

// workspaceKey names the prepared workspace a grant's worker could start
// from in this sandbox: the grant's volume, its path inside the workspace,
// the sandbox's workspace disk and the template's runner user. It reports
// false without prepared workspaces, a valid grant, or a template that
// records its runner user.
func (m *Manager) workspaceKey(meta Metadata, grant *protocol.CheckoutGrant) (checkout.WorkspaceKey, bool) {
	if m.workspaces == nil || m.checkouts == nil || grant == nil || grant.ID == "" {
		return checkout.WorkspaceKey{}, false
	}
	rel, err := filepath.Rel(guestWorkspace, grant.Path)
	if err != nil || filepath.Clean(grant.Path) != grant.Path || rel == "." || strings.HasPrefix(rel, "..") {
		return checkout.WorkspaceKey{}, false
	}
	tmpl, err := m.store.Get(meta.Template, meta.Tag)
	if err != nil {
		return checkout.WorkspaceKey{}, false
	}
	uid, gid, ok := tmpl.RunnerOwner()
	if !ok {
		return checkout.WorkspaceKey{}, false
	}
	key := checkout.WorkspaceKey{
		Scope: grant.Scope, Generation: grant.Generation, Path: rel,
		Bytes: vm.FileSize(filepath.Join(vm.RootDir(m.cfg.JailBase, meta.ID), firecracker.WorkspacePath)),
		UID:   uid, GID: gid,
	}
	return key, key.Valid()
}

func (m *Manager) recorder(record bool, key checkout.WorkspaceKey) checkout.Recorder {
	if !record {
		return nil
	}
	return func() checkout.Recording { return m.workspaces.Recorder(key) }
}

// preparedWorkspace gives a fresh sandbox the node's prepared workspace for
// key before its first worker starts, so the guest finds the repository in
// place instead of seeding it. The guest unmounts its empty workspace, a
// reflink of the image replaces the disk file, Firecracker reopens the drive
// and the guest mounts it. Any failure before the swap leaves the empty
// workspace mounted and the worker seeds as usual; one after it puts the
// empty disk back.
func (m *Manager) preparedWorkspace(ctx context.Context, sb *Sandbox, inst vm.Instance, agent vsock.Agent, key checkout.WorkspaceKey, log *slog.Logger) bool {
	image, ok := m.workspaces.Lookup(key)
	if !ok || inst == nil || agent == nil {
		return false
	}
	start := time.Now()
	sb.mu.Lock()
	meta, root := sb.meta, sb.root
	sb.mu.Unlock()
	uid := m.cfg.UIDBase + meta.Slot
	workspace := filepath.Join(root, firecracker.WorkspacePath)
	staged, empty := workspace+".prepared", workspace+".empty"
	_ = os.Remove(staged)
	if err := m.cloneFile(image, staged); err != nil {
		log.Warn("prepared workspace not used", "scope", key.Scope, "error", err)
		return false
	}
	defer os.Remove(staged)
	if err := vm.Chown(staged, uid, uid); err != nil {
		log.Warn("prepared workspace not used", "scope", key.Scope, "error", err)
		return false
	}
	if code, err := vsock.RunProcess(ctx, agent, vsock.ExecRequest{Cmd: []string{"/bin/umount", guestWorkspace}, Cwd: "/", TimeoutMs: 10_000}, nil); err != nil || code != 0 {
		log.Warn("prepared workspace not used: the guest kept its workspace mounted", "scope", key.Scope, "exit_code", code, "error", err)
		return false
	}
	configure := vsock.ConfigureRequest{Hostname: meta.Hostname, DNS: m.cfg.DNS}
	swap := func(from, to string) error {
		if err := os.Rename(workspace, to); err != nil {
			return err
		}
		if err := os.Rename(from, workspace); err != nil {
			return errors.Join(err, os.Rename(to, workspace))
		}
		return inst.API().PatchDrive(ctx, firecracker.DrivePatch{DriveID: firecracker.WorkspaceDriveID, PathOnHost: inst.GuestPath(firecracker.WorkspacePath)})
	}
	err := swap(staged, empty)
	if err == nil {
		err = agent.Configure(ctx, configure)
	}
	if err != nil {
		// Back to the empty disk, which the guest mounted before.
		if vm.Exists(empty) {
			restoreErr := swap(empty, staged)
			err = errors.Join(err, restoreErr)
		}
		err = errors.Join(err, agent.Configure(ctx, configure))
		log.Warn("prepared workspace not used", "scope", key.Scope, "error", err)
		return false
	}
	_ = os.Remove(empty)
	log.Info("prepared workspace used", "scope", key.Scope, "duration", time.Since(start))
	return true
}
