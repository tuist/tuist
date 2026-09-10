package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
)

type session struct {
	auth   string
	node   string
	frames chan []byte
	conn   *websocket.Conn
}

// fakeServer accepts node connections and hands each one to the test.
type fakeServer struct {
	sessions chan *session
}

func (f *fakeServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != ConnectPath {
		http.NotFound(w, r)
		return
	}
	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	s := &session{auth: r.Header.Get("Authorization"), node: r.Header.Get("X-Tuist-Node-Name"), frames: make(chan []byte, 64), conn: conn}
	ctx := context.Background()
	go func() {
		for {
			_, data, err := conn.Read(ctx)
			if err != nil {
				close(s.frames)
				return
			}
			s.frames <- data
		}
	}()
	f.sessions <- s
}

func (s *session) next(t *testing.T) any {
	t.Helper()
	select {
	case data, ok := <-s.frames:
		if !ok {
			t.Fatal("connection closed")
		}
		frame, err := protocol.Decode(data)
		if err != nil {
			t.Fatalf("decode %s: %v", data, err)
		}
		return frame
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for frame")
	}
	return nil
}

func (s *session) send(t *testing.T, v any) {
	t.Helper()
	data, _ := json.Marshal(v)
	if err := s.conn.Write(context.Background(), websocket.MessageText, data); err != nil {
		t.Fatal(err)
	}
}

func TestClientSession(t *testing.T) {
	fs := &fakeServer{sessions: make(chan *session, 4)}
	srv := httptest.NewServer(fs)
	defer srv.Close()

	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("tok-1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	var handled []string
	var mu sync.Mutex
	handler := func(ctx context.Context, cmd protocol.Command, stream func(protocol.Stream)) protocol.Result {
		mu.Lock()
		handled = append(handled, cmd.Op)
		mu.Unlock()
		switch cmd.Op {
		case "exec":
			stream(protocol.Stream{Stream: "stdout", DataB64: "aGk="})
			return protocol.OKResult(cmd.ID, protocol.ExecResult{ExitCode: 0})
		case "slow":
			time.Sleep(200 * time.Millisecond)
			return protocol.OKResult(cmd.ID, nil)
		default:
			return protocol.ErrorResult(cmd.ID, errUnknown)
		}
	}
	reports := 0
	c := New(Config{
		URL: "http" + strings.TrimPrefix(srv.URL, "http"), NodeName: "node-a", TokenPath: tokenPath,
		Hello: func() protocol.Hello {
			return protocol.Hello{DaemonVersion: "test", FirecrackerVersion: "v1.16.1", Capacity: protocol.Capacity{CPUs: 4}, Templates: []protocol.TemplateInfo{{Name: "default", Tag: "t1", Ready: true, Shapes: []string{}}}}
		},
		Report: func() protocol.Report {
			reports++
			return protocol.Report{Sandboxes: []protocol.SandboxInfo{}, Memory: protocol.MemoryReport{UsedBytes: 1}}
		},
		Handler: handler, ReportInterval: 50 * time.Millisecond, MinBackoff: 10 * time.Millisecond, MaxBackoff: 50 * time.Millisecond,
	})
	c.Emit(protocol.Event{Event: protocol.EventTemplateReady, Name: "default", Tag: "t1", Shape: "2x4096"})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() {
		c.Run(ctx)
		close(done)
	}()

	s := <-fs.sessions
	if s.auth != "Bearer tok-1" || s.node != "node-a" {
		t.Fatalf("headers auth=%q node=%q", s.auth, s.node)
	}
	hello, ok := s.next(t).(*protocol.Hello)
	if !ok || hello.Node != "node-a" || hello.DaemonVersion != "test" || hello.Capacity.CPUs != 4 || len(hello.Templates) != 1 {
		t.Fatalf("hello %+v", hello)
	}
	// The event queued before the connection is delivered right after hello.
	event, ok := s.next(t).(*protocol.Event)
	if !ok || event.Event != protocol.EventTemplateReady || event.Shape != "2x4096" {
		t.Fatalf("event %+v", event)
	}

	// Commands run concurrently: the slow one is issued first but the exec
	// result arrives first.
	s.send(t, protocol.Command{Type: protocol.FrameCommand, ID: "c1", Op: "slow", Args: json.RawMessage(`{}`)})
	s.send(t, protocol.Command{Type: protocol.FrameCommand, ID: "c2", Op: "exec", Args: json.RawMessage(`{"sandbox_id":"s","cmd":["ls"]}`)})
	var got []string
	seen := map[string]bool{}
	for !(seen["result:c1"] && seen["result:c2"]) {
		switch frame := s.next(t).(type) {
		case *protocol.Stream:
			if frame.ID != "c2" || frame.Stream != "stdout" || frame.DataB64 != "aGk=" {
				t.Fatalf("stream %+v", frame)
			}
			got = append(got, "stream:"+frame.ID)
		case *protocol.Result:
			got = append(got, "result:"+frame.ID)
			seen["result:"+frame.ID] = true
		case *protocol.Report:
			if frame.Memory.UsedBytes != 1 {
				t.Fatalf("report %+v", frame)
			}
			got = append(got, "report")
		default:
			t.Fatalf("unexpected frame %T", frame)
		}
	}
	joined := strings.Join(got, ",")
	if !strings.Contains(joined, "stream:c2,result:c2") || !strings.Contains(joined, "result:c1") || strings.Index(joined, "result:c2") > strings.Index(joined, "result:c1") {
		t.Fatalf("frames %v", got)
	}
	if !strings.Contains(joined, "report") {
		// Reports fire every 50ms; the slow command took 200ms, so at
		// least one must have been interleaved.
		t.Fatalf("expected a report among %v", got)
	}
	s.send(t, protocol.Command{Type: protocol.FrameCommand, ID: "c3", Op: "bogus"})
	for {
		frame := s.next(t)
		if res, ok := frame.(*protocol.Result); ok {
			if res.ID != "c3" || res.OK || res.Error == "" {
				t.Fatalf("bogus result %+v", res)
			}
			break
		}
	}
	// Frames that are not commands are ignored, not fatal.
	s.send(t, protocol.Event{Type: protocol.FrameEvent, Event: "noise"})
	s.send(t, map[string]string{"type": "garbage"})

	// Drop the connection: the client reconnects with a re-read token.
	if err := os.WriteFile(tokenPath, []byte("tok-2"), 0o600); err != nil {
		t.Fatal(err)
	}
	s.conn.Close(websocket.StatusGoingAway, "bye")
	s2 := <-fs.sessions
	if s2.auth != "Bearer tok-2" {
		t.Fatalf("token not re-read on reconnect: %q", s2.auth)
	}
	if _, ok := s2.next(t).(*protocol.Hello); !ok {
		t.Fatal("expected hello on reconnect")
	}
	if !c.Connected() {
		t.Fatal("client should report connected")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return after cancel")
	}
	mu.Lock()
	defer mu.Unlock()
	if strings.Join(handled, ",") != "slow,exec,bogus" {
		t.Fatalf("handled %v", handled)
	}
}

func TestClientRetriesWhenServerIsDown(t *testing.T) {
	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("tok"), 0o600); err != nil {
		t.Fatal(err)
	}
	fs := &fakeServer{sessions: make(chan *session, 1)}
	srv := httptest.NewUnstartedServer(fs)
	c := New(Config{URL: "http://127.0.0.1:1", NodeName: "n", TokenPath: tokenPath, Hello: func() protocol.Hello { return protocol.Hello{} },
		Handler: func(ctx context.Context, cmd protocol.Command, stream func(protocol.Stream)) protocol.Result {
			return protocol.OKResult(cmd.ID, nil)
		},
		MinBackoff: 5 * time.Millisecond, MaxBackoff: 20 * time.Millisecond})
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	start := time.Now()
	c.Run(ctx)
	if time.Since(start) < 250*time.Millisecond {
		t.Fatal("Run returned before the context ended")
	}
	if c.Connected() {
		t.Fatal("should not be connected")
	}
	srv.Close()
}

func TestEmitDropsOldestWhenFull(t *testing.T) {
	c := New(Config{})
	for i := 0; i < eventQueueSize+5; i++ {
		c.Emit(protocol.Event{Event: "e", SandboxID: string(rune('a' + i%26))})
	}
	if len(c.events) != eventQueueSize {
		t.Fatalf("queue length %d", len(c.events))
	}
	first := <-c.events
	if first.Type != protocol.FrameEvent {
		t.Fatalf("event type not defaulted: %+v", first)
	}
}

var errUnknown = errorString("unknown op")

type errorString string

func (e errorString) Error() string { return string(e) }
