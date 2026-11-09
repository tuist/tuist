package sandbox

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/hostinfo"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

// Operations is the command surface Dispatch drives; *Manager implements
// it.
type Operations interface {
	Create(ctx context.Context, args protocol.CreateArgs) (protocol.CreateResult, error)
	Resume(ctx context.Context, id string) (protocol.ResumeResult, error)
	PauseWith(ctx context.Context, args protocol.PauseArgs) (protocol.PauseResult, error)
	Delete(ctx context.Context, id string) error
	Exec(ctx context.Context, args protocol.ExecArgs, out vsock.OutputFunc) (protocol.ExecResult, error)
	StartWorker(ctx context.Context, args protocol.StartWorkerArgs) (protocol.StartWorkerResult, error)
	StopWorker(ctx context.Context, id string) error
	Status(ctx context.Context, id string) (protocol.SandboxInfo, error)
	SaveDisks(ctx context.Context, args protocol.SaveDisksArgs) (protocol.SaveDisksResult, error)
	DeleteDisks(ctx context.Context, id string) error
	Archive(ctx context.Context, args protocol.ArchiveArgs) (protocol.ArchiveResult, error)
	ArchiveDisks(ctx context.Context, args protocol.ArchiveDisksArgs) (protocol.ArchiveResult, error)
}

// Lifecycle operations run detached from the connection that carried the
// command: a dropped WebSocket must not abort a snapshot half-way. These
// bound them instead.
const (
	createTimeout = 15 * time.Minute
	resumeTimeout = 5 * time.Minute
	pauseTimeout  = 10 * time.Minute
	saveTimeout   = 10 * time.Minute
	deleteTimeout = 2 * time.Minute
	// An archive streams up to the sandbox's full disk ceiling to object
	// storage.
	archiveTimeout = 30 * time.Minute

	maxExecStreamBytes = 2 << 20
)

// reclaimMemory serves the reclaim command the server sends before it
// shrinks the daemon's Pod. A variable so tests do not touch the host's
// cgroup.
var reclaimMemory = hostinfo.Reclaim

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
		var args protocol.PauseArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(pauseTimeout)
		defer cancel()
		res, err := ops.PauseWith(opCtx, args)
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
		if args.Claim != nil {
			return claimedExec(ctx, ops, cmd.ID, args)
		}
		// The server keeps at most a megabyte of output per exec; anything
		// past maxExecStreamBytes is dropped here instead of crossing the
		// WebSocket. The command itself runs to completion.
		var streamed int
		out := func(name string, data []byte) {
			if stream == nil || streamed >= maxExecStreamBytes {
				return
			}
			if streamed+len(data) > maxExecStreamBytes {
				data = data[:maxExecStreamBytes-streamed]
			}
			streamed += len(data)
			stream(protocol.Stream{Type: protocol.FrameStream, ID: cmd.ID, Stream: name, DataB64: base64.StdEncoding.EncodeToString(data)})
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
	case protocol.OpSaveDisks:
		var args protocol.SaveDisksArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(saveTimeout)
		defer cancel()
		res, err := ops.SaveDisks(opCtx, args)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, res)
	case protocol.OpDeleteDisks:
		var args protocol.DiskSnapshotArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(deleteTimeout)
		defer cancel()
		if err := ops.DeleteDisks(opCtx, args.SnapshotID); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, map[string]any{})
	case protocol.OpArchive:
		var args protocol.ArchiveArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(archiveTimeout)
		defer cancel()
		res, err := ops.Archive(opCtx, args)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, res)
	case protocol.OpArchiveDisks:
		var args protocol.ArchiveDisksArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		opCtx, cancel := detached(archiveTimeout)
		defer cancel()
		res, err := ops.ArchiveDisks(opCtx, args)
		if err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, res)
	case protocol.OpReclaim:
		var args protocol.ReclaimArgs
		if err := decode(&args); err != nil {
			return protocol.ErrorResult(cmd.ID, err)
		}
		return protocol.OKResult(cmd.ID, reclaimMemory(args.TargetBytes))
	default:
		return protocol.ErrorResult(cmd.ID, fmt.Errorf("unknown op %q", cmd.Op))
	}
}

const maxClaimTimeout = time.Minute

// claimedExec waits for the exec's claim and runs it with the claimed
// value. Its output goes only to the claimer; the server learns the exit
// code, or that the claim expired with the VM untouched.
func claimedExec(ctx context.Context, ops Operations, id string, args protocol.ExecArgs) protocol.Result {
	provider, ok := ops.(interface{ Claims() *Claims })
	if !ok {
		return protocol.ErrorResult(id, errors.New("exec: claims are not supported"))
	}
	digest, err := hex.DecodeString(args.Claim.NonceSHA256)
	timeout := time.Duration(args.Claim.TimeoutMs) * time.Millisecond
	if err != nil || len(digest) != sha256.Size || args.Claim.Env == "" || timeout <= 0 || timeout > maxClaimTimeout {
		return protocol.ErrorResult(id, errors.New("exec: invalid claim"))
	}
	offer, claimed, err := provider.Claims().wait(ctx, args.SandboxID, [sha256.Size]byte(digest), timeout)
	if err != nil {
		return protocol.ErrorResult(id, err)
	}
	if !claimed {
		return protocol.OKResult(id, protocol.ExecResult{Unclaimed: true})
	}
	env := make(map[string]string, len(args.Env)+1)
	maps.Copy(env, args.Env)
	env[args.Claim.Env] = offer.value
	args.Env = env
	var stdout []byte
	res, err := ops.Exec(ctx, args, func(name string, data []byte) {
		if name == "stdout" && len(stdout) < maxExecStreamBytes {
			stdout = append(stdout, data[:min(len(data), maxExecStreamBytes-len(stdout))]...)
		}
	})
	offer.outcome <- ClaimOutcome{ExitCode: res.ExitCode, Stdout: stdout, Err: err}
	if err != nil {
		return protocol.ErrorResult(id, err)
	}
	return protocol.OKResult(id, res)
}
