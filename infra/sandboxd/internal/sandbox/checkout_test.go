package sandbox

import (
	"bufio"
	"bytes"
	"context"
	"io"
	"net"
	"strconv"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

type seedingAgent struct{}

func (seedingAgent) Seed(context.Context, protocol.CheckoutGrant) (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader([]byte("tree"))), nil
}

func (seedingAgent) Export(context.Context, protocol.CheckoutGrant, io.Reader) error { return nil }

func TestWorkerWithACheckoutGrantIsServedWhileItRuns(t *testing.T) {
	h := newHarness(t)
	h.m.checkouts = seedingAgent{}
	ctx := context.Background()
	h.create(t, testID, 10)
	inst := h.launcher.Instances()[1]
	socket := inst.VsockPath() + "_" + strconv.Itoa(protocol.CheckoutVsockPort)
	grant := &protocol.CheckoutGrant{ID: "11111111-1111-4111-8111-111111111111", Commit: "0123456789abcdef0123456789abcdef01234567", Path: "/workspace/repo"}
	env := map[string]string{"ANTHROPIC_WORK_SECRET": "s3cret"}
	if _, err := h.m.StartWorker(ctx, protocol.StartWorkerArgs{SandboxID: testID, Env: env, Checkout: grant}); err != nil {
		t.Fatal(err)
	}
	workerEnv, _ := inst.Agent.RequestsOf("exec")[0]["env"].(map[string]any)
	if workerEnv["ANTHROPIC_WORK_SECRET"] != "s3cret" || workerEnv[protocol.CheckoutPathEnv] != "/workspace/repo" ||
		workerEnv[protocol.CheckoutCommitEnv] != grant.Commit || workerEnv[protocol.CheckoutVsockEnv] != "5002" {
		t.Fatalf("worker env %v", workerEnv)
	}
	if len(env) != 1 {
		t.Fatalf("the server's env map was changed: %v", env)
	}
	conn, err := net.Dial("unix", socket)
	if err != nil {
		t.Fatalf("checkout port not armed: %v", err)
	}
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	conn.Write([]byte(`{"op":"seed"}` + "\n"))
	answer, _ := io.ReadAll(bufio.NewReader(conn))
	conn.Close()
	if string(answer) != "{\"ok\":true}\ntree" {
		t.Fatalf("seed answered %q", answer)
	}
	if err := h.m.StopWorker(ctx, testID); err != nil {
		t.Fatal(err)
	}
	if conn, err := net.Dial("unix", socket); err == nil {
		conn.Close()
		t.Fatal("checkout port still armed after the worker exited")
	}
	// A pause is possible again, and nothing is served across it.
	if _, err := h.m.Pause(ctx, testID); err != nil {
		t.Fatal(err)
	}
}

func TestWorkerWithoutCheckoutKeepsItsEnv(t *testing.T) {
	for name, tc := range map[string]struct {
		agent checkout.Agent
		grant *protocol.CheckoutGrant
	}{
		"no grant":      {seedingAgent{}, nil},
		"no agent":      {nil, &protocol.CheckoutGrant{ID: "u", Path: "/workspace/repo"}},
		"relative path": {seedingAgent{}, &protocol.CheckoutGrant{ID: "u", Path: "repo"}},
		"unclean path":  {seedingAgent{}, &protocol.CheckoutGrant{ID: "u", Path: "/workspace/../repo"}},
		"no use":        {seedingAgent{}, &protocol.CheckoutGrant{Path: "/workspace/repo"}},
	} {
		t.Run(name, func(t *testing.T) {
			h := newHarness(t)
			h.m.checkouts = tc.agent
			h.create(t, testID, 10)
			inst := h.launcher.Instances()[1]
			if _, err := h.m.StartWorker(context.Background(), protocol.StartWorkerArgs{SandboxID: testID, Checkout: tc.grant}); err != nil {
				t.Fatalf("the worker did not start: %v", err)
			}
			workerEnv, _ := inst.Agent.RequestsOf("exec")[0]["env"].(map[string]any)
			for _, key := range []string{protocol.CheckoutPathEnv, protocol.CheckoutCommitEnv, protocol.CheckoutVsockEnv} {
				if _, ok := workerEnv[key]; ok {
					t.Fatalf("worker env %v carries %s", workerEnv, key)
				}
			}
			if conn, err := net.Dial("unix", inst.VsockPath()+"_"+strconv.Itoa(protocol.CheckoutVsockPort)); err == nil {
				conn.Close()
				t.Fatal("checkout port armed")
			}
			h.m.StopWorker(context.Background(), testID)
		})
	}
}
