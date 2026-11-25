package sandbox

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"os"
	"strconv"
	"strings"
	"syscall"

	"github.com/tuist/tuist/infra/sandboxd/internal/blobcache"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

const executorPath = "/usr/local/bin/sbx-executor"

// executionScope is the CAS scope of a remote-execution action exec, with
// the project credential the server issued. The server writes a scheduled
// action's request itself. A claimed action's request comes from the
// claimer, so its scope is the one the server pinned in the claim, and only
// when the request names that scope: the node's cache answers a hit without
// asking the CAS, so a scope must never come from someone the credential
// does not bind. Nothing comes from the guest.
func executionScope(args protocol.ExecArgs) (blobcache.Scope, bool) {
	token, request := args.Env["SBX_EXECUTION_TOKEN"], args.Env["SBX_EXECUTION_REQUEST"]
	if len(args.Cmd) != 1 || args.Cmd[0] != executorPath || token == "" {
		return blobcache.Scope{}, false
	}
	r, ok := requestScope(request)
	if !ok {
		return blobcache.Scope{}, false
	}
	if args.Claim != nil {
		if args.Claim.Scope == nil || !sameScope(*args.Claim.Scope, r) {
			return blobcache.Scope{}, false
		}
		r = *args.Claim.Scope
	}
	if !(strings.HasPrefix(r.Endpoint, "grpc://") || strings.HasPrefix(r.Endpoint, "grpcs://")) {
		return blobcache.Scope{}, false
	}
	return blobcache.Scope{Endpoint: r.Endpoint, Account: r.Account, Instance: r.Instance, Token: token}, true
}

// requestScope reads the CAS scope an action request names.
func requestScope(request string) (protocol.ExecutionScope, bool) {
	var r protocol.ExecutionScope
	if request == "" || json.Unmarshal([]byte(request), &r) != nil {
		return r, false
	}
	return r, true
}

// sameScope reports whether a request names the pinned scope. Account and
// project handles are case-insensitive, as the server resolves them.
func sameScope(pinned, requested protocol.ExecutionScope) bool {
	return pinned.Endpoint == requested.Endpoint &&
		strings.EqualFold(pinned.Account, requested.Account) &&
		strings.EqualFold(pinned.Instance, requested.Instance)
}

// claimedScopeMismatch reports a claimed action whose request names a scope
// other than the one the server authorized; it must not run.
func claimedScopeMismatch(args protocol.ExecArgs, value string) bool {
	if args.Claim.Scope == nil || len(args.Cmd) != 1 || args.Cmd[0] != executorPath {
		return false
	}
	r, ok := requestScope(value)
	return !ok || !sameScope(*args.Claim.Scope, r)
}

// serveBlobs lets an executing action's guest read input blobs from the
// node's cache for as long as the exec runs, until the guest seals the
// channel. Without it the guest's connection is refused and it reads the CAS
// itself. The returned function stops serving.
func (m *Manager) serveBlobs(sb *Sandbox, args protocol.ExecArgs) func() {
	if m.blobs == nil {
		return func() {}
	}
	scope, ok := executionScope(args)
	if !ok {
		return func() {}
	}
	sb.mu.Lock()
	inst, tag := sb.inst, sb.meta.Tag
	sb.mu.Unlock()
	// Only the template deployed with this daemon is known to seal before
	// the command runs; older tags kept ready for a rollout read the CAS.
	if inst == nil || tag == "" || tag != m.DefaultTemplateTag() {
		return func() {}
	}
	path := inst.VsockPath() + "_" + strconv.Itoa(blobcache.GuestPort)
	listener, err := listenForVMM(path, inst.Root())
	if err != nil {
		m.log.Warn("serving blobs to the guest", "sandbox", args.SandboxID, "error", err)
		return func() {}
	}
	m.scopeLog(args.SandboxID, scope).Info("serving blobs to the guest")
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		m.blobs.Serve(ctx, listener, scope)
	}()
	return func() {
		cancel()
		<-done
		os.Remove(path)
	}
}

// listenForVMM listens on the Unix socket Firecracker forwards guest
// connections to. The jailed Firecracker runs as the owner of its jail root.
func listenForVMM(path, root string) (net.Listener, error) {
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(root)
	if err == nil {
		if st, ok := info.Sys().(*syscall.Stat_t); ok {
			err = os.Chown(path, int(st.Uid), int(st.Gid))
		}
	}
	if err == nil {
		err = os.Chmod(path, 0o600)
	}
	if err != nil {
		listener.Close()
		return nil, err
	}
	return listener, nil
}

// inputsWorkspace gives an execution VM its scope's inputs image as its
// workspace before the action's exec runs, so the guest executor links the
// image's blobs into the action root instead of reading them over vsock
// (blobcache.Image). It happens at most once per VM, only for the template
// deployed with this daemon, and any failure leaves the VM's own workspace.
func (m *Manager) inputsWorkspace(ctx context.Context, sb *Sandbox, agent vsock.Agent, args protocol.ExecArgs) {
	if m.blobs == nil {
		return
	}
	scope, ok := executionScope(args)
	if !ok {
		return
	}
	sb.mu.Lock()
	inst, tag, swapped, workspaceGB := sb.inst, sb.meta.Tag, sb.inputsSwapped, sb.meta.WorkspaceGB
	sb.inputsSwapped = true
	sb.mu.Unlock()
	if inst == nil || swapped || tag == "" || tag != m.DefaultTemplateTag() || workspaceGB <= 0 {
		return
	}
	image, ok := m.blobs.Image(scope, int64(workspaceGB)<<30)
	if !ok {
		return
	}
	m.swapWorkspace(ctx, sb, inst, agent, image, m.scopeLog(args.SandboxID, scope), "inputs image")
}

// scopeLog records whose cached inputs a VM reads, for forensics.
func (m *Manager) scopeLog(sandboxID string, scope blobcache.Scope) *slog.Logger {
	return m.log.With("sandbox", sandboxID, "scope", scope.Key(), "account", scope.Account, "instance", scope.Instance, "endpoint", scope.Endpoint)
}
