package sandbox

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

type claimOps struct {
	fakeOps
	claims *Claims
	env    map[string]string
}

func (c *claimOps) Claims() *Claims { return c.claims }

func (c *claimOps) Exec(ctx context.Context, args protocol.ExecArgs, out vsock.OutputFunc) (protocol.ExecResult, error) {
	c.env = args.Env
	return c.fakeOps.Exec(ctx, args, out)
}

func claimCommand(nonce string, timeoutMs int64) protocol.Command {
	digest := sha256.Sum256([]byte(nonce))
	args, _ := json.Marshal(protocol.ExecArgs{
		SandboxID: "s1", Cmd: []string{"/usr/local/bin/sbx-executor"}, Env: map[string]string{"TOKEN": "t"}, TimeoutMs: 1000,
		Claim: &protocol.ClaimArgs{NonceSHA256: hex.EncodeToString(digest[:]), Env: "REQUEST", TimeoutMs: timeoutMs},
	})
	return protocol.Command{ID: "c1", Op: protocol.OpExec, Args: args}
}

func TestClaimedExecRunsWithTheClaimedValue(t *testing.T) {
	ops := &claimOps{claims: NewClaims()}
	results := make(chan protocol.Result, 1)
	var streamed []protocol.Stream
	go func() {
		results <- Dispatch(context.Background(), ops, claimCommand("nonce", 5000), func(s protocol.Stream) { streamed = append(streamed, s) })
	}()

	outcome, err := ops.claims.Claim(context.Background(), "s1", []byte("nonce"), `{"hash":"h"}`, time.Second)
	if err != nil {
		t.Fatalf("claim: %v", err)
	}
	if outcome.ExitCode != 3 || string(outcome.Stdout) != "hello\n" || outcome.Err != nil {
		t.Fatalf("outcome %+v", outcome)
	}
	res := <-results
	if !res.OK || res.Data.(protocol.ExecResult).Unclaimed || res.Data.(protocol.ExecResult).ExitCode != 3 {
		t.Fatalf("result %+v", res)
	}
	if ops.env["TOKEN"] != "t" || ops.env["REQUEST"] != `{"hash":"h"}` {
		t.Fatalf("env %v", ops.env)
	}
	if len(streamed) != 0 {
		t.Fatalf("claimed output must go only to the claimer: %+v", streamed)
	}
}

func TestUnclaimedExecExpiresWithoutRunning(t *testing.T) {
	ops := &claimOps{claims: NewClaims()}
	res := Dispatch(context.Background(), ops, claimCommand("nonce", 20), nil)
	if !res.OK || !res.Data.(protocol.ExecResult).Unclaimed || len(ops.calls) != 0 {
		t.Fatalf("result %+v calls %v", res, ops.calls)
	}
	if _, err := ops.claims.Claim(context.Background(), "s1", []byte("nonce"), "{}", 10*time.Millisecond); !errors.Is(err, ErrClaimRefused) {
		t.Fatalf("an expired claim must be refused: %v", err)
	}
}

func TestClaimIsSingleUseAndNeedsTheNonce(t *testing.T) {
	ops := &claimOps{claims: NewClaims()}
	results := make(chan protocol.Result, 1)
	go func() { results <- Dispatch(context.Background(), ops, claimCommand("nonce", 5000), nil) }()

	if _, err := ops.claims.Claim(context.Background(), "s1", []byte("guess"), "{}", time.Second); !errors.Is(err, ErrClaimRefused) {
		t.Fatalf("wrong nonce: %v", err)
	}
	if _, err := ops.claims.Claim(context.Background(), "s1", []byte("nonce"), "{}", time.Second); err != nil {
		t.Fatalf("a wrong nonce must not consume the claim: %v", err)
	}
	<-results
	if _, err := ops.claims.Claim(context.Background(), "s1", []byte("nonce"), "{}", 10*time.Millisecond); !errors.Is(err, ErrClaimRefused) {
		t.Fatalf("second claim: %v", err)
	}
}

func TestClaimWaitsForTheExecToRegister(t *testing.T) {
	ops := &claimOps{claims: NewClaims()}
	claimed := make(chan error, 1)
	go func() {
		_, err := ops.claims.Claim(context.Background(), "s1", []byte("nonce"), "{}", time.Second)
		claimed <- err
	}()
	time.Sleep(20 * time.Millisecond)
	res := Dispatch(context.Background(), ops, claimCommand("nonce", 5000), nil)
	if err := <-claimed; err != nil || !res.OK || res.Data.(protocol.ExecResult).Unclaimed {
		t.Fatalf("claim %v result %+v", err, res)
	}
}

func TestClaimedExecNeedsClaimSupport(t *testing.T) {
	res := Dispatch(context.Background(), &fakeOps{}, claimCommand("nonce", 20), nil)
	if res.OK {
		t.Fatalf("result %+v", res)
	}
}
