package macosandbox

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	transport "github.com/tuist/tuist/infra/sandboxd/pkg/server"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Exercises the shipped transport, dispatcher, journal and Kubernetes capacity
// adapter together. Apple Virtualization is replaced here; the opt-in runtime
// test separately exercises real guest execution and saved memory.
func TestNativeControlPlaneAcceptance(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	m, runtime, _, args := harness(t)
	capacity, node, _ := capacityFixture()
	m.Capacity = capacity
	var current atomic.Pointer[Manager]
	current.Store(m)
	sessions := make(chan *websocket.Conn, 4)
	var tokens atomic.Int32
	endpoint := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer minted-host-token" || r.Header.Get("X-Tuist-Node-Name") != node.Name {
			http.Error(w, "unauthorized", 401)
			return
		}
		conn, err := websocket.Accept(w, r, nil)
		if err == nil {
			sessions <- conn
		}
	}))
	defer endpoint.Close()
	client := transport.New(transport.Config{URL: endpoint.URL, NodeName: node.Name, Token: func(context.Context) (string, error) { tokens.Add(1); return "minted-host-token", nil },
		Hello: func() protocol.Hello {
			return protocol.Hello{Platform: "darwin", Generation: m.NodeUID, ControlUID: capacity.ControlUID, Sandboxes: current.Load().Snapshot()}
		},
		Report: func() protocol.Report {
			return protocol.Report{Platform: "darwin", Generation: m.NodeUID, Sandboxes: current.Load().Snapshot()}
		},
		Handler: func(ctx context.Context, cmd protocol.Command, out func(protocol.Stream)) protocol.Result {
			return current.Load().Dispatch(ctx, cmd, out)
		},
		MinBackoff: time.Millisecond, MaxBackoff: 10 * time.Millisecond, ReportInterval: time.Hour})
	done := make(chan struct{})
	go func() { client.Run(ctx); close(done) }()
	defer func() { cancel(); <-done }()
	connect := func() *websocket.Conn {
		t.Helper()
		select {
		case conn := <-sessions:
			_, data, err := conn.Read(ctx)
			if err != nil {
				t.Fatal(err)
			}
			var hello protocol.Hello
			if json.Unmarshal(data, &hello) != nil || hello.Platform != "darwin" || hello.Generation != m.NodeUID {
				t.Fatalf("bad authenticated hello %s", data)
			}
			return conn
		case <-ctx.Done():
			t.Fatal(ctx.Err())
			return nil
		}
	}
	conn := connect()
	call := func(op string, fields map[string]any, wantOK bool) {
		t.Helper()
		fields["sandbox_id"] = args.SandboxID
		fields["node_uid"] = m.NodeUID
		raw, _ := json.Marshal(fields)
		command, _ := json.Marshal(protocol.Command{Type: protocol.FrameCommand, ID: op, Op: op, Args: raw})
		if err := conn.Write(ctx, websocket.MessageText, command); err != nil {
			t.Fatal(err)
		}
		for {
			_, raw, err := conn.Read(ctx)
			if err != nil {
				t.Fatal(err)
			}
			frame, err := protocol.Decode(raw)
			if err != nil {
				t.Fatal(err)
			}
			if result, ok := frame.(*protocol.Result); ok {
				if result.ID != op || result.OK != wantOK {
					t.Fatalf("%s: %+v", op, result)
				}
				return
			}
		}
	}
	call("create", map[string]any{"template": "macos", "vcpus": 8, "memory_mb": 8192, "workspace_gb": 10}, true)
	call("exec", map[string]any{"cmd": []string{"memory-proof"}}, true)
	call("pause", map[string]any{}, true)
	if !m.Snapshot()[0].Resident {
		t.Fatal("resident pause released capacity")
	}
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: runtime, Capacity: capacity}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	current.Store(recovered)
	call("resume", map[string]any{}, true)
	call("start_worker", map[string]any{"env": map[string]string{"ANTHROPIC_WORK_ID": "work-1", "ANTHROPIC_WORK_SECRET": "stdin-only"}}, true)
	node.Annotations = nil
	if _, err := capacity.Kube.CoreV1().Nodes().Update(ctx, node, metav1.UpdateOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if !recovered.Snapshot()[0].Resident {
		t.Fatal("interrupted active work")
	}
	call("stop_worker", map[string]any{}, true)
	if err := recovered.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if recovered.Snapshot()[0].Resident || recovered.Snapshot()[0].FinishedWorkID != "work-1" {
		t.Fatal("eviction/completion proof missing")
	}
	call("resume", map[string]any{}, false)
	grant, _ := json.Marshal(Grant{CPUMilli: 16000, MemoryBytes: 48 * 1024 * 1024 * 1024, Slots: 2, Allow: true, NodeUID: m.NodeUID, ControlUID: capacity.ControlUID, ObservedAt: time.Now()})
	node.Annotations = map[string]string{GrantAnnotation: string(grant)}
	if _, err := capacity.Kube.CoreV1().Nodes().Update(ctx, node, metav1.UpdateOptions{}); err != nil {
		t.Fatal(err)
	}
	call("resume", map[string]any{}, true)
	conn.CloseNow()
	conn = connect()
	if tokens.Load() < 2 {
		t.Fatal("reconnect reused a token")
	}
	call("exec", map[string]any{"cmd": []string{"memory-proof"}}, true)
	call("delete", map[string]any{}, true)
	if len(recovered.Snapshot()) != 0 || runtime.creates != 1 {
		t.Fatal("cold boot or leaked ownership")
	}
	pods, err := capacity.Kube.CoreV1().Pods(Namespace).List(ctx, metav1.ListOptions{})
	if err != nil || len(pods.Items) != 0 {
		t.Fatal(fmt.Sprintf("reservation cleanup: %v %+v", err, pods))
	}
}
