package agent

import (
	"context"
	"errors"
	"os"
	"sync"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandbox-image/internal/protocol"
)

const actionExecID = "rbe-single-action"

// SingleAction is enabled only by an image-owned rootfs marker. The claim file
// persists through agent restarts and is never removed: each VM handles at most
// one action. Its template snapshot is taken before this file or credentials exist.
type SingleAction struct {
	ClaimPath  string
	Run        func(context.Context, string, string) (string, error)
	PrepareCAS func(context.Context, string) error
	mu         sync.Mutex
	cancel     context.CancelFunc
}

// Preparation never consumes the action claim or receives credentials. A used
// VM, including one whose agent restarted, cannot be prepared for another action.
func (a *SingleAction) Prepare(ctx context.Context, req *protocol.Request, w *protocol.Writer) error {
	if err := w.Send(protocol.Started(req.ID, "rbe-cas-prepare")); err != nil {
		return err
	}
	_, err := os.Stat(a.ClaimPath)
	if !os.IsNotExist(err) || a.PrepareCAS == nil || len(req.Env) != 0 {
		return w.Send(protocol.Exit(req.ID, 1))
	}
	// Creating the claim is the action's first write to its filesystem. A
	// sibling file faults that path in without consuming the claim.
	if f, err := os.OpenFile(a.ClaimPath+".prepare", os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600); err == nil {
		_ = f.Close()
		_ = os.Remove(f.Name())
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if err := a.PrepareCAS(ctx, req.Cmd[2]); err != nil {
		return w.Send(protocol.Exit(req.ID, 1))
	}
	return w.Send(protocol.Exit(req.ID, 0))
}

func (a *SingleAction) Execute(ctx context.Context, req *protocol.Request, w *protocol.Writer) error {
	claim, err := os.OpenFile(a.ClaimPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return errors.New("execution VM already used or unavailable")
	}
	if err := claim.Close(); err != nil {
		return errors.New("execution claim failed")
	}
	limit := 12 * time.Minute
	if req.TimeoutMs > 0 && req.TimeoutMs < int64(limit/time.Millisecond) {
		limit = time.Duration(req.TimeoutMs) * time.Millisecond
	}
	ctx, cancel := context.WithTimeout(ctx, limit)
	a.mu.Lock()
	a.cancel = cancel
	a.mu.Unlock()
	defer func() { cancel(); a.mu.Lock(); a.cancel = nil; a.mu.Unlock() }()
	if err := w.Send(protocol.Started(req.ID, actionExecID)); err != nil {
		return err
	}
	output, err := a.Run(ctx, req.Env["SBX_EXECUTION_REQUEST"], req.Env["SBX_EXECUTION_TOKEN"])
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return w.Send(protocol.Exit(req.ID, 124))
	}
	if err != nil {
		// Do not return errors containing credentials, endpoints or request content.
		return w.Send(protocol.Exit(req.ID, 1))
	}
	if err := w.Send(protocol.Stream(req.ID, protocol.TypeStdout, []byte(output))); err != nil {
		return err
	}
	return w.Send(protocol.Exit(req.ID, 0))
}

func (a *SingleAction) Kill(signal syscall.Signal) error {
	if signal != 0 && signal != syscall.SIGTERM && signal != syscall.SIGKILL {
		return errors.New("unsupported execution signal")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.cancel == nil {
		return errors.New("no running action")
	}
	a.cancel()
	return nil
}
