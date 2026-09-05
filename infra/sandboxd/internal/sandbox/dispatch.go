package sandbox

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

// Operations is the command surface Dispatch drives; *Manager implements
// it.
type Operations interface {
	Create(ctx context.Context, args protocol.CreateArgs) (protocol.CreateResult, error)
	Resume(ctx context.Context, id string) (protocol.ResumeResult, error)
	Pause(ctx context.Context, id string) (protocol.PauseResult, error)
	Delete(ctx context.Context, id string) error
	Exec(ctx context.Context, args protocol.ExecArgs, out vsock.OutputFunc) (protocol.ExecResult, error)
	StartWorker(ctx context.Context, args protocol.StartWorkerArgs) (protocol.StartWorkerResult, error)
	StopWorker(ctx context.Context, id string) error
	Status(ctx context.Context, id string) (protocol.SandboxInfo, error)
}

// Lifecycle operations run detached from the connection that carried the
// command: a dropped WebSocket must not abort a snapshot half-way. These
// bound them instead.
const (
	createTimeout = 15 * time.Minute
	resumeTimeout = 5 * time.Minute
	pauseTimeout  = 10 * time.Minute
	deleteTimeout = 2 * time.Minute
)

// Dispatch runs one command and returns its single result. stream receives
// exec output frames before the result.
func Dispatch(ctx context.Context, ops Operations, cmd protocol.Command, stream func(protocol.Stream)) protocol.Result {
	decode := func(v any) error {
		if len(cmd.Args) == 0 {
			return fmt.Errorf("%s: missing args", cmd.Op)
		}
		if err := json.Unmarshal(cmd.Args, v); err != nil {
			return fmt.Errorf("%s: decoding args: %w", cmd.Op, err)
		}
		return nil
	}
	detached := func(timeout time.Duration) (context.Context, context.CancelFunc) {
		return context.WithTimeout(context.WithoutCancel(ctx), timeout)
	}
	switch cmd.Op {
	case protocol.OpCreate:
		var args protocol.CreateArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(createTimeout)
		defer cancel()
		res, err := ops.Create(opCtx, args)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, res)
	case protocol.OpResume:
		var args protocol.SandboxArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(resumeTimeout)
		defer cancel()
		res, err := ops.Resume(opCtx, args.SandboxID)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, res)
	case protocol.OpPause:
		var args protocol.SandboxArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(pauseTimeout)
		defer cancel()
		res, err := ops.Pause(opCtx, args.SandboxID)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, res)
	case protocol.OpDelete:
		var args protocol.SandboxArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(deleteTimeout)
		defer cancel()
		if err := ops.Delete(opCtx, args.SandboxID); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, map[string]any{})
	case protocol.OpExec:
		var args protocol.ExecArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		out := func(name string, data []byte) {
			if stream != nil {
				stream(protocol.Stream{Type: protocol.FrameStream, ID: cmd.ID, Stream: name, DataB64: base64.StdEncoding.EncodeToString(data)})
			}
		}
		res, err := ops.Exec(ctx, args, out)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, res)
	case protocol.OpStartWorker:
		var args protocol.StartWorkerArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		res, err := ops.StartWorker(ctx, args)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, res)
	case protocol.OpStopWorker:
		var args protocol.SandboxArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		if err := ops.StopWorker(ctx, args.SandboxID); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, map[string]any{})
	case protocol.OpStatus:
		var args protocol.SandboxArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		info, err := ops.Status(ctx, args.SandboxID)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, info)
	default:
		return protocol.ErrorResult(cmd.ID, fmt.Errorf("unknown op %q", cmd.Op))
	}
}
