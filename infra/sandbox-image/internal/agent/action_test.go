package agent

import (
	"context"
	"errors"
	"github.com/tuist/tuist/infra/sandbox-image/internal/protocol"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

func actionRequest() protocol.Request {
	return protocol.Request{ID: "request", Op: protocol.OpExec, Cmd: []string{"/usr/local/bin/sbx-executor"}, Env: map[string]string{"SBX_EXECUTION_REQUEST": "request-json", "SBX_EXECUTION_TOKEN": "secret"}}
}
func TestEmbeddedActionRunsOnceIncludingAfterRestart(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	claim := filepath.Join(t.TempDir(), "claim")
	var calls atomic.Int32
	runner := func(_ context.Context, request, token string) (string, error) {
		calls.Add(1)
		if request != "request-json" || token != "secret" {
			t.Error("request was not forwarded")
		}
		return "result\n", nil
	}
	h.Action = &SingleAction{ClaimPath: claim, Run: runner}
	frames := roundTrip(t, h, actionRequest())
	out, _, code, _ := collect(t, frames)
	if out != "result\n" || code == nil || *code != 0 || frames[0].ExecID != actionExecID {
		t.Fatalf("frames: %v", frames)
	}
	info, err := os.Stat(claim)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("claim mode: %v %v", info, err)
	}
	// A new handler simulates the supervised agent restarting in the same VM.
	h.Action = &SingleAction{ClaimPath: claim, Run: runner}
	frames = roundTrip(t, h, actionRequest())
	if calls.Load() != 1 || len(frames) != 1 || frames[0].Type != protocol.TypeError {
		t.Fatalf("replayed: %v", frames)
	}
}
func TestEmbeddedActionKillWaitsForRunner(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	finished := make(chan struct{})
	h.Action = &SingleAction{ClaimPath: filepath.Join(t.TempDir(), "claim"), Run: func(ctx context.Context, _, _ string) (string, error) {
		<-ctx.Done()
		close(finished)
		return "", ctx.Err()
	}}
	c := dial(t, h)
	c.send(actionRequest())
	started := c.next()
	frames := roundTrip(t, h, protocol.Request{ID: "kill", Op: protocol.OpKill, Target: started.ExecID})
	if len(frames) != 1 || frames[0].Type != protocol.TypeOK {
		t.Fatalf("kill: %v", frames)
	}
	rest := c.rest()
	<-finished
	if len(rest) != 1 || rest[0].Type != protocol.TypeExit || *rest[0].Code != 1 {
		t.Fatalf("exit: %v", rest)
	}
}
func TestEmbeddedActionTimeoutAndErrorDoNotLeakCredentials(t *testing.T) {
	for _, timeout := range []bool{false, true} {
		t.Run(map[bool]string{false: "error", true: "timeout"}[timeout], func(t *testing.T) {
			h := newHandler(&fakeSystem{}, t.TempDir())
			h.Action = &SingleAction{ClaimPath: filepath.Join(t.TempDir(), "claim"), Run: func(ctx context.Context, _, _ string) (string, error) {
				if timeout {
					<-ctx.Done()
				}
				return "secret", errors.New("secret")
			}}
			req := actionRequest()
			req.TimeoutMs = 1
			frames := roundTrip(t, h, req)
			_, _, code, _ := collect(t, frames)
			expected := 1
			if timeout {
				expected = 124
			}
			if code == nil || *code != expected {
				t.Fatalf("frames: %v", frames)
			}
			for _, f := range frames {
				if strings.Contains(f.Message, "secret") || f.DataB64 != "" {
					t.Fatal("credential leaked")
				}
			}
		})
	}
}
func TestEmbeddedActionDoesNotInterceptOrdinaryCommands(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	h.Action = &SingleAction{ClaimPath: filepath.Join(t.TempDir(), "claim"), Run: func(context.Context, string, string) (string, error) {
		t.Error("ordinary command intercepted")
		return "", nil
	}}
	frames := roundTrip(t, h, protocol.Request{ID: "normal", Op: protocol.OpExec, Cmd: []string{"/bin/echo", "normal"}})
	output, _, code, _ := collect(t, frames)
	if output != "normal\n" || code == nil || *code != 0 {
		t.Fatalf("frames: %v", frames)
	}
	if _, err := os.Stat(h.Action.ClaimPath); !os.IsNotExist(err) {
		t.Fatal("normal command claimed VM")
	}
}

func TestEmbeddedActionConcurrentClaims(t *testing.T) {
	var calls atomic.Int32
	action := &SingleAction{ClaimPath: filepath.Join(t.TempDir(), "claim"), Run: func(context.Context, string, string) (string, error) { calls.Add(1); return "result", nil }}
	var group sync.WaitGroup
	for i := 0; i < 16; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			req := actionRequest()
			_ = action.Execute(context.Background(), &req, protocol.NewWriter(io.Discard))
		}()
	}
	group.Wait()
	if calls.Load() != 1 {
		t.Fatalf("executed %d times", calls.Load())
	}
}

func TestPreparationDoesNotConsumeClaimOrAcceptCredentials(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	claim := filepath.Join(t.TempDir(), "claim")
	var prepared atomic.Int32
	h.Action = &SingleAction{ClaimPath: claim, PrepareCAS: func(_ context.Context, endpoint string) error {
		if endpoint != "grpc://cache" {
			t.Error("wrong endpoint")
		}
		prepared.Add(1)
		return nil
	}, Run: func(context.Context, string, string) (string, error) { return "result", nil }}
	req := protocol.Request{ID: "prepare", Op: protocol.OpExec, Cmd: []string{"/usr/local/bin/sbx-executor", "--prepare-cas", "grpc://cache"}}
	frames := roundTrip(t, h, req)
	_, _, code, _ := collect(t, frames)
	if code == nil || *code != 0 || prepared.Load() != 1 {
		t.Fatalf("preparation: %v", frames)
	}
	if _, err := os.Stat(claim); !os.IsNotExist(err) {
		t.Fatal("preparation consumed action claim")
	}
	req.Env = map[string]string{"SBX_EXECUTION_TOKEN": "secret"}
	frames = roundTrip(t, h, req)
	_, _, code, _ = collect(t, frames)
	if code == nil || *code != 1 || prepared.Load() != 1 {
		t.Fatal("preparation accepted credentials")
	}
	roundTrip(t, h, actionRequest())
	req.Env = nil
	frames = roundTrip(t, h, req)
	_, _, code, _ = collect(t, frames)
	if code == nil || *code != 1 || prepared.Load() != 1 {
		t.Fatal("used VM prepared again")
	}
}
