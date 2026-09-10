package vsock

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeAgent answers the guest side of the protocol over net.Pipe.
type fakeAgent struct {
	mu       sync.Mutex
	requests []request
	kills    []request
	// exec drives an exec request; frames it returns are written in order.
	exec func(req request, write func(response))
}

func (f *fakeAgent) dialer(t *testing.T) Dialer {
	return func(ctx context.Context) (net.Conn, error) {
		client, server := net.Pipe()
		go f.serve(t, server)
		return client, nil
	}
}

func (f *fakeAgent) serve(t *testing.T, c net.Conn) {
	defer c.Close()
	reader := bufio.NewReader(c)
	line, err := reader.ReadString('\n')
	if err != nil {
		return
	}
	if !strings.HasPrefix(line, "CONNECT 5000\n") {
		t.Errorf("bad handshake line %q", line)
		return
	}
	if _, err := c.Write([]byte("OK 1024\n")); err != nil {
		return
	}
	line, err = reader.ReadString('\n')
	if err != nil {
		return
	}
	var req request
	if err := json.Unmarshal([]byte(line), &req); err != nil {
		t.Errorf("bad request %q: %v", line, err)
		return
	}
	f.mu.Lock()
	f.requests = append(f.requests, req)
	if req.Op == "kill" {
		f.kills = append(f.kills, req)
	}
	f.mu.Unlock()
	write := func(resp response) {
		resp.ID = req.ID
		data, _ := json.Marshal(resp)
		_, _ = c.Write(append(data, '\n'))
	}
	switch req.Op {
	case "ping":
		write(response{Type: "pong", UptimeS: 12.5, AgentVersion: "test"})
	case "set_time", "configure", "write_file", "kill":
		write(response{Type: "ok"})
	case "exec":
		f.exec(req, write)
	default:
		write(response{Type: "error", Message: "unknown op"})
	}
}

func newClient(t *testing.T, f *fakeAgent) *Client {
	return NewClient(func(ctx context.Context) (net.Conn, error) {
		client, server := net.Pipe()
		go f.serve(t, server)
		if err := Handshake(ctx, client, 5000); err != nil {
			client.Close()
			return nil, err
		}
		return client, nil
	})
}

func TestSimpleRequests(t *testing.T) {
	f := &fakeAgent{}
	c := newClient(t, f)
	ctx := context.Background()
	pong, err := c.Ping(ctx)
	if err != nil || pong.UptimeS != 12.5 || pong.AgentVersion != "test" {
		t.Fatalf("ping: %+v %v", pong, err)
	}
	now := time.Unix(1757000000, 0)
	if err := c.SetTime(ctx, now); err != nil {
		t.Fatal(err)
	}
	if err := c.Configure(ctx, ConfigureRequest{Hostname: "sbx-abc", DNS: []string{"10.128.0.10"}, FormatWorkspace: true}); err != nil {
		t.Fatal(err)
	}
	if err := c.WriteFile(ctx, "/workspace/x", 0o644, []byte("hi")); err != nil {
		t.Fatal(err)
	}
	if err := c.Kill(ctx, "e1", 15); err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.requests) != 5 {
		t.Fatalf("got %d requests", len(f.requests))
	}
	if f.requests[1].Op != "set_time" || f.requests[1].UnixNanos != now.UnixNano() {
		t.Fatalf("set_time request %+v", f.requests[1])
	}
	cfg := f.requests[2]
	if cfg.Op != "configure" || cfg.Hostname != "sbx-abc" || len(cfg.DNS) != 1 || !cfg.FormatWorkspace {
		t.Fatalf("configure request %+v", cfg)
	}
	wf := f.requests[3]
	if wf.Op != "write_file" || wf.Path != "/workspace/x" || wf.Mode != 0o644 || wf.DataB64 != base64.StdEncoding.EncodeToString([]byte("hi")) {
		t.Fatalf("write_file request %+v", wf)
	}
	kill := f.requests[4]
	if kill.Op != "kill" || kill.Target != "e1" || kill.Signal != 15 {
		t.Fatalf("kill request %+v", kill)
	}
	ids := map[string]bool{}
	for _, r := range f.requests {
		if r.ID == "" || ids[r.ID] {
			t.Fatalf("request ids must be unique and non-empty: %+v", f.requests)
		}
		ids[r.ID] = true
	}
}

func TestExecStreamsAndExits(t *testing.T) {
	f := &fakeAgent{}
	f.exec = func(req request, write func(response)) {
		if req.Cmd[0] != "/bin/bash" || req.Cwd != "/workspace" || req.Env["K"] != "V" || req.TimeoutMs != 1000 {
			t.Errorf("exec request %+v", req)
		}
		write(response{Type: "started", ExecID: "e7"})
		write(response{Type: "stdout", DataB64: base64.StdEncoding.EncodeToString([]byte("hello\n"))})
		write(response{Type: "stderr", DataB64: base64.StdEncoding.EncodeToString([]byte("warn\n"))})
		write(response{Type: "exit", Code: 3})
	}
	c := newClient(t, f)
	var mu sync.Mutex
	var chunks []string
	code, err := c.Exec(context.Background(), ExecRequest{Cmd: []string{"/bin/bash", "-lc", "ls"}, Env: map[string]string{"K": "V"}, Cwd: "/workspace", TimeoutMs: 1000},
		func(stream string, data []byte) {
			mu.Lock()
			chunks = append(chunks, stream+":"+string(data))
			mu.Unlock()
		})
	if err != nil {
		t.Fatal(err)
	}
	if code != 3 {
		t.Fatalf("exit code %d", code)
	}
	if strings.Join(chunks, "|") != "stdout:hello\n|stderr:warn\n" {
		t.Fatalf("chunks %q", chunks)
	}
}

func TestExecErrorFrame(t *testing.T) {
	f := &fakeAgent{}
	f.exec = func(req request, write func(response)) {
		write(response{Type: "error", Message: "no such file"})
	}
	c := newClient(t, f)
	_, err := c.Exec(context.Background(), ExecRequest{Cmd: []string{"/nope"}}, nil)
	var agentErr *AgentError
	if !errors.As(err, &agentErr) || agentErr.Message != "no such file" {
		t.Fatalf("expected agent error, got %v", err)
	}
}

func TestExecCancellationKillsViaSecondConnection(t *testing.T) {
	f := &fakeAgent{}
	release := make(chan struct{})
	f.exec = func(req request, write func(response)) {
		write(response{Type: "started", ExecID: "e9"})
		<-release
		write(response{Type: "exit", Code: 137})
	}
	c := newClient(t, f)
	ctx, cancel := context.WithCancel(context.Background())
	proc, err := c.Start(ctx, ExecRequest{Cmd: []string{"sleep"}}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if proc.ID() != "e9" {
		t.Fatalf("exec id %q", proc.ID())
	}
	go func() {
		time.Sleep(20 * time.Millisecond)
		cancel()
	}()
	_, err = RunProcessWait(ctx, proc)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected cancellation, got %v", err)
	}
	deadline := time.Now().Add(time.Second)
	for {
		f.mu.Lock()
		kills := len(f.kills)
		var last request
		if kills > 0 {
			last = f.kills[0]
		}
		f.mu.Unlock()
		if kills > 0 {
			if last.Target != "e9" || last.Signal != 9 {
				t.Fatalf("kill request %+v", last)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("no kill request sent after cancellation")
		}
		time.Sleep(5 * time.Millisecond)
	}
	close(release)
	if code, err := proc.Wait(context.Background()); err != nil || code != 137 {
		t.Fatalf("wait after release: %d %v", code, err)
	}
}

func TestHandshakeRejectsBadReply(t *testing.T) {
	client, server := net.Pipe()
	go func() {
		reader := bufio.NewReader(server)
		_, _ = reader.ReadString('\n')
		_, _ = server.Write([]byte("nope\n"))
		server.Close()
	}()
	err := Handshake(context.Background(), client, 5000)
	if err == nil || !strings.Contains(err.Error(), "unexpected reply") {
		t.Fatalf("expected handshake error, got %v", err)
	}
}

func TestWaitReadyRetriesUntilAgentAnswers(t *testing.T) {
	var attempts int
	var mu sync.Mutex
	c := NewClient(func(ctx context.Context) (net.Conn, error) {
		mu.Lock()
		attempts++
		n := attempts
		mu.Unlock()
		if n < 3 {
			return nil, errors.New("connection refused")
		}
		client, server := net.Pipe()
		f := &fakeAgent{}
		go f.serve(t, server)
		if err := Handshake(ctx, client, 5000); err != nil {
			return nil, err
		}
		return client, nil
	})
	pong, err := c.WaitReady(context.Background(), 2*time.Second)
	if err != nil || pong.AgentVersion != "test" {
		t.Fatalf("wait ready: %+v %v", pong, err)
	}
	mu.Lock()
	defer mu.Unlock()
	if attempts != 3 {
		t.Fatalf("attempts %d", attempts)
	}
}
