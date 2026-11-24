package sandbox

import (
	"context"
	"encoding/json"
	"errors"
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

// executionScope is the CAS scope of a remote-execution action exec: the
// endpoint, account and instance the server or gateway put in its request, and
// the project credential the server issued. Nothing comes from the guest.
func executionScope(args protocol.ExecArgs) (blobcache.Scope, bool) {
	token, request := args.Env["SBX_EXECUTION_TOKEN"], args.Env["SBX_EXECUTION_REQUEST"]
	if len(args.Cmd) != 1 || args.Cmd[0] != executorPath || token == "" || request == "" {
		return blobcache.Scope{}, false
	}
	var r struct {
		Endpoint string `json:"endpoint"`
		Account  string `json:"account"`
		Instance string `json:"instance"`
	}
	if json.Unmarshal([]byte(request), &r) != nil ||
		!(strings.HasPrefix(r.Endpoint, "grpc://") || strings.HasPrefix(r.Endpoint, "grpcs://")) {
		return blobcache.Scope{}, false
	}
	return blobcache.Scope{Endpoint: r.Endpoint, Account: r.Account, Instance: r.Instance, Token: token}, true
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
	m.swapWorkspace(ctx, sb, inst, agent, image, m.log.With("sandbox", args.SandboxID), "inputs image")
}
