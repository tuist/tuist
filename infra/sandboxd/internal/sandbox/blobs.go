package sandbox

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"

	"github.com/tuist/tuist/infra/sandboxd/internal/blobcache"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
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
	inst, tag, drives := sb.inst, sb.meta.Tag, sb.meta.InputDrives
	sb.mu.Unlock()
	// Only the template deployed with this daemon is known to seal before
	// the command runs; older tags kept ready for a rollout read the CAS.
	if inst == nil || tag == "" || tag != m.cfg.DefaultTemplateTag {
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
		m.blobs.Serve(ctx, listener, scope, attachInputs(inst, drives))
	}()
	return func() {
		cancel()
		<-done
		os.Remove(path)
	}
}

// attachInputs attaches input tree images to the VM's input drives in order.
// The image is hard-linked over the drive's placeholder in the jail, where it
// stays read-only to the jailed Firecracker (root-owned, mode 0444, and a
// read-only drive), and the patch makes Firecracker reopen the drive and the
// guest re-read its capacity. A VM runs one action and is never reused, so a
// drive is never detached.
func attachInputs(inst vm.Instance, drives int) blobcache.Attach {
	if drives == 0 {
		return nil
	}
	var mu sync.Mutex
	next := 0
	return func(ctx context.Context, image string) (int, error) {
		mu.Lock()
		defer mu.Unlock()
		if next >= drives {
			return 0, blobcache.ErrNoDrive
		}
		i := next
		// A failed attach still spends the drive: its placeholder is gone.
		next++
		if err := vm.HardLink(image, filepath.Join(inst.Root(), firecracker.InputPath(i))); err != nil {
			return 0, err
		}
		if err := inst.API().PatchDrive(ctx, firecracker.DrivePatch{DriveID: firecracker.InputDriveID(i), PathOnHost: inst.GuestPath(firecracker.InputPath(i))}); err != nil {
			return 0, err
		}
		return i, nil
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
